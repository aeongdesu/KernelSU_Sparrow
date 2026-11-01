#!/system/bin/sh
set -u

TARGET="${PVR_WHITELIST_PATH:-/data/system/users/0/pvr_white_list.xml}"
PACKAGE="${PVR_PACKAGE:-df.root}"

die() {
    echo "[ERROR]: $*" >&2
    exit 1
}

[ -f "$TARGET" ] || exit 0

esc=$(printf '%s' "$PACKAGE" | sed 's/\./\\./g')
Q="[\"']"

grep -Eq "packagename[[:space:]]*=[[:space:]]*${Q}${esc}${Q}" "$TARGET" || exit 0

tmp="${TARGET}.rm.$$"
trap 'rm -f "$tmp"' EXIT

awk -v re="<(ns2:)?item[^>]*packagename[[:space:]]*=[[:space:]]*${Q}${esc}${Q}[^>]*>" '
    {
        gsub(re, "")
        if ($0 ~ /^[[:space:]]*$/) next
        print
    }
' "$TARGET" > "$tmp" || die "failed to rewrite $TARGET"

grep -Eq '</(ns2:)?whitelist-packages>' "$tmp" || die "refusing to write malformed $TARGET"

if grep -Eq '<(ns2:)?item' "$tmp"; then
    chown system:system "$tmp" || die "could not set owner on $tmp"
    chmod 0644 "$tmp" || die "could not set mode on $tmp"
    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$tmp" 2>/dev/null || true
    fi
    mv -f "$tmp" "$TARGET" || die "failed to replace $TARGET"
    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$TARGET" 2>/dev/null || true
    fi
    echo "removed $PACKAGE from $TARGET"
else
    rm -f "$tmp"
    rm -f "$TARGET"
    echo "removed $TARGET"
fi
trap - EXIT
