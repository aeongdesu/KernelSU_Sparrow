#!/system/bin/sh
set -u

TARGET="${PVR_WHITELIST_PATH:-/data/system/users/0/pvr_white_list.xml}"
PACKAGE="${PVR_PACKAGE:-df.root}"
TYPE="${PVR_TYPE:-vr}"

die() {
    echo "[ERROR]: $*" >&2
    exit 1
}

set_attrs() {
    chown system:system "$1" || return 1
    chmod 0644 "$1" || return 1
    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$1" 2>/dev/null || true
    fi
    return 0
}

esc=$(printf '%s' "$PACKAGE" | sed 's/\./\\./g')
PKG_RE="packagename[[:space:]]*=[[:space:]]*[\"']${esc}[\"']"

[ -d "$(dirname "$TARGET")" ] || die "directory $(dirname "$TARGET") does not exist"

if [ -f "$TARGET" ] && grep -Eq "$PKG_RE" "$TARGET"; then
    set_attrs "$TARGET" || die "could not set attributes on $TARGET"
    echo "$PACKAGE already whitelisted in $TARGET"
    exit 0
fi

tmp="${TARGET}.new.$$"
trap 'rm -f "$tmp"' EXIT

if [ -s "$TARGET" ] && grep -q '[^[:space:]]' "$TARGET"; then
    grep -q '</\(ns2:\)\{0,1\}whitelist-packages>' "$TARGET" ||
        die "$TARGET has no </whitelist-packages> tag; refusing to edit"
    # insert before the closing tag on its own line
    awk -v pkg="$PACKAGE" -v typ="$TYPE" '
        {
            sub(/<\/(ns2:)?whitelist-packages>/,
                "    <item packagename=\"" pkg "\" type=\"" typ "\" />\n&")
            print
        }
    ' "$TARGET" > "$tmp" || die "failed to rewrite $TARGET"
else
    {
        echo '<?xml version="1.0" encoding="utf-8"?>'
        echo '<whitelist-packages>'
        echo "    <item packagename=\"$PACKAGE\" type=\"$TYPE\" />"
        echo '</whitelist-packages>'
    } > "$tmp" || die "failed to create $tmp"
fi

set_attrs "$tmp" || die "could not set attributes on $tmp"
mv -f "$tmp" "$TARGET" || die "failed to replace $TARGET"
set_attrs "$TARGET" || die "could not set attributes on $TARGET"
trap - EXIT

echo "whitelisted $PACKAGE as $TYPE in $TARGET"
