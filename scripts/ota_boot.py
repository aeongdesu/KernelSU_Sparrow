#!/usr/bin/env python3
"""Extract kheaders.tar.xz and kernel.config from an OTA payload.

Only the boot partition's byte range is fetched, not the whole archive.
"""

from __future__ import annotations

import bz2
import hashlib
import lzma
import os
import struct
import sys
import urllib.request
import zlib

BLOCK = 4096
OP_REPLACE = 0
OP_REPLACE_BZ = 1
OP_REPLACE_XZ = 8


def http_range(url: str, start: int, end: int) -> bytes:
    req = urllib.request.Request(url, headers={"Range": f"bytes={start}-{end}"})
    with urllib.request.urlopen(req, timeout=60) as fh:
        if fh.status != 206 or fh.headers.get("Content-Range", "").split("/")[0] != f"bytes {start}-{end}":
            raise SystemExit("server did not honor the HTTP range request")
        data = fh.read(end - start + 1)
    if len(data) != end - start + 1:
        raise SystemExit("truncated HTTP range response")
    return data


def url_size(url: str) -> int:
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as fh:
        return int(fh.headers["Content-Length"])


def varint(buf: bytes, pos: int) -> tuple[int, int]:
    value = shift = 0
    while True:
        byte = buf[pos]
        pos += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, pos
        shift += 7


def fields(buf: bytes):
    pos = 0
    while pos < len(buf):
        key, pos = varint(buf, pos)
        num, wire = key >> 3, key & 7
        if wire == 0:
            value, pos = varint(buf, pos)
        elif wire == 1:
            value, pos = buf[pos:pos + 8], pos + 8
        elif wire == 2:
            length, pos = varint(buf, pos)
            value, pos = buf[pos:pos + length], pos + length
        elif wire == 5:
            value, pos = buf[pos:pos + 4], pos + 4
        else:
            return
        yield num, wire, value


def zip_entry(url: str, size: int, wanted: str) -> tuple[int, int]:
    """Return (data_offset, compressed_size) for a stored zip entry."""
    tail_start = max(0, size - 200_000)
    tail = http_range(url, tail_start, size - 1)

    locator = tail.rfind(b"PK\x06\x07")
    if locator < 0:
        raise SystemExit("ZIP64 locator not found")
    # The locator points at the ZIP64 end-of-central-directory record, whose
    # own fields give the real central-directory offset and size.
    z64 = struct.unpack("<Q", tail[locator + 8:locator + 16])[0] - tail_start
    if z64 < 0 or z64 + 56 > len(tail):
        raise SystemExit("central directory outside fetched tail")
    cd_offset = struct.unpack("<Q", tail[z64 + 48:z64 + 56])[0]
    cd_size = struct.unpack("<Q", tail[z64 + 40:z64 + 48])[0]
    cd = http_range(url, cd_offset, cd_offset + cd_size - 1)

    pos = 0
    while pos < len(cd) and cd[pos:pos + 4] == b"PK\x01\x02":
        name_len, extra_len, comment_len = struct.unpack("<HHH", cd[pos + 28:pos + 34])
        compressed = struct.unpack("<I", cd[pos + 20:pos + 24])[0]
        local_offset = struct.unpack("<I", cd[pos + 42:pos + 46])[0]
        name = cd[pos + 46:pos + 46 + name_len].decode()
        extra = cd[pos + 46 + name_len:pos + 46 + name_len + extra_len]

        walk = 0
        while walk + 4 <= len(extra):
            tag, length = struct.unpack("<HH", extra[walk:walk + 4])
            if tag == 1:
                values = extra[walk + 4:walk + 4 + length]
                cursor = 0
                if struct.unpack("<I", cd[pos + 24:pos + 28])[0] == 0xFFFFFFFF:
                    cursor += 8
                if compressed == 0xFFFFFFFF:
                    compressed = struct.unpack("<Q", values[cursor:cursor + 8])[0]
                    cursor += 8
                if local_offset == 0xFFFFFFFF:
                    local_offset = struct.unpack("<Q", values[cursor:cursor + 8])[0]
            walk += 4 + length

        if name == wanted:
            return local_offset, compressed
        pos += 46 + name_len + extra_len + comment_len

    raise SystemExit(f"{wanted} not found in OTA zip")


def payload_data_offset(url: str, local_header: int) -> int:
    header = http_range(url, local_header, local_header + 29)
    name_len, extra_len = struct.unpack("<HH", header[26:30])
    return local_header + 30 + name_len + extra_len


def boot_operations(manifest: bytes) -> list[tuple[int, int, int, int, int]]:
    for num, wire, part in fields(manifest):
        if num != 13 or wire != 2:
            continue
        members = list(fields(part))
        name = next((v.decode() for n, w, v in members if n == 1 and w == 2), None)
        if name != "boot":
            continue
        operations = []
        for n, w, op in members:
            if n != 8:
                continue
            kind = data_offset = data_length = None
            extents = []
            for f, ww, v in fields(op):
                if f == 1:
                    kind = v
                elif f == 2:
                    data_offset = v
                elif f == 3:
                    data_length = v
                elif f == 6:
                    start = count = None
                    for ff, _, vv in fields(v):
                        if ff == 1:
                            start = vv
                        elif ff == 2:
                            count = vv
                    extents.append((start, count))
            for start, count in extents:
                operations.append((kind, data_offset, data_length, start, count))
        return operations
    raise SystemExit("boot partition not found in payload manifest")


def carve(kernel: bytes) -> tuple[bytes, bytes]:
    headers = None
    for offset in range(len(kernel) - 6):
        if kernel[offset:offset + 6] != b"\xfd7zXZ\x00":
            continue
        try:
            unpacked = lzma.decompress(kernel[offset:])
        except Exception:
            continue
        if unpacked[:2] == b"./":
            headers = unpacked
            break
    if headers is None:
        raise SystemExit("kheaders archive not found in kernel")

    config = None
    offset = kernel.find(b"\x1f\x8b\x08")
    while 0 <= offset < len(kernel):
        try:
            decoder = zlib.decompressobj(31)
            unpacked = decoder.decompress(kernel[offset:])
        except Exception:
            offset = kernel.find(b"\x1f\x8b\x08", offset + 1)
            continue
        if b"CONFIG_" in unpacked[:4096]:
            config = unpacked
            break
        offset = kernel.find(b"\x1f\x8b\x08", offset + 1)
    if config is None:
        raise SystemExit("kernel config not found in kernel")

    return headers, config


def main() -> None:
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "build"
    url = os.environ["OTA_URL"]
    expected_boot = os.environ["OTA_BOOT_SHA256"]

    os.makedirs(out_dir, exist_ok=True)
    size = url_size(url)
    local_header, _ = zip_entry(url, size, "payload.bin")
    data_offset = payload_data_offset(url, local_header)

    header = http_range(url, data_offset, data_offset + 23)
    if header[:4] != b"CrAU":
        raise SystemExit("payload.bin is not an update payload")
    manifest_size = struct.unpack(">Q", header[12:20])[0]
    signature_size = struct.unpack(">I", header[20:24])[0]
    manifest = http_range(url, data_offset + 24, data_offset + 24 + manifest_size - 1)
    data_base = data_offset + 24 + manifest_size + signature_size

    operations = boot_operations(manifest)
    lowest = min(op[1] for op in operations)
    highest = max(op[1] + op[2] for op in operations)
    blob = http_range(url, data_base + lowest, data_base + highest - 1)

    blocks = max(start + count for _, _, _, start, count in operations)
    image = bytearray(blocks * BLOCK)
    for kind, offset, length, start, count in operations:
        chunk = blob[offset - lowest:offset - lowest + length]
        if kind == OP_REPLACE_XZ:
            raw = lzma.decompress(chunk)
        elif kind == OP_REPLACE_BZ:
            raw = bz2.decompress(chunk)
        elif kind == OP_REPLACE:
            raw = chunk
        else:
            raise SystemExit(f"unsupported install operation {kind}")
        if len(raw) != count * BLOCK:
            raise SystemExit(f"operation size mismatch: {len(raw)} != {count * BLOCK}")
        image[start * BLOCK:(start + count) * BLOCK] = raw

    actual = hashlib.sha256(image).hexdigest()
    if actual != expected_boot:
        raise SystemExit(f"boot image hash mismatch\n  expected {expected_boot}\n  actual   {actual}")

    if image[:8] != b"ANDROID!" or struct.unpack("<I", image[40:44])[0] not in (3, 4):
        raise SystemExit("expected an Android boot image with header version 3 or 4")
    kernel_size = struct.unpack("<I", image[8:12])[0]
    kernel = bytes(image[4096:4096 + kernel_size])

    headers, config = carve(kernel)
    with open(os.path.join(out_dir, "kheaders.tar.xz"), "wb") as fh:
        fh.write(lzma.compress(headers, format=lzma.FORMAT_XZ))
    with open(os.path.join(out_dir, "kernel.config"), "wb") as fh:
        fh.write(config)

    canary = [line.split()[-1] for line in headers.decode("utf-8", "replace").splitlines()
              if "TSK_STACK_CANARY" in line]
    print(f"boot image verified, kheaders {len(headers)} bytes, config {len(config)} bytes")
    print(f"TSK_STACK_CANARY {canary}")
    if canary != ["1744"]:
        raise SystemExit("unexpected TSK_STACK_CANARY")


if __name__ == "__main__":
    main()
