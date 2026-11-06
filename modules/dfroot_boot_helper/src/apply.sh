#!/system/bin/sh
set -u

MODDIR=$(dirname "$0")

die() {
    echo "[ERROR]: $*" >&2
    exit 1
}

. "$MODDIR/common.sh"

if pvr_whitelisted; then
    pvr_attrs "$PVR_WL" || die "could not set attributes on $PVR_WL"
    echo "$PVR_PKG already whitelisted in $PVR_WL"
    exit 0
fi

tmp="${PVR_WL}.new.$$"
trap 'rm -f "$tmp"' EXIT

if [ -s "$PVR_WL" ] && grep -q '[^[:space:]]' "$PVR_WL"; then
    grep -q '</\(ns2:\)\{0,1\}whitelist-packages>' "$PVR_WL" ||
        die "$PVR_WL has no </whitelist-packages> tag; refusing to edit"
    # insert before the closing tag so minified documents stay valid
    awk -v pkg="$PVR_PKG" '
        {
            sub(/<\/(ns2:)?whitelist-packages>/,
                "    <item packagename=\"" pkg "\" type=\"vr\" />\n&")
            print
        }
    ' "$PVR_WL" > "$tmp" || die "failed to rewrite $PVR_WL"
else
    {
        echo '<?xml version="1.0" encoding="utf-8"?>'
        echo '<whitelist-packages>'
        echo "    <item packagename=\"$PVR_PKG\" type=\"vr\" />"
        echo '</whitelist-packages>'
    } > "$tmp" || die "failed to create $tmp"
fi

pvr_replace "$tmp" || die "could not write $PVR_WL"
trap - EXIT

echo "whitelisted $PVR_PKG in $PVR_WL"
