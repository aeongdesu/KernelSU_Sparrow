#!/system/bin/sh

PVR_PKG="${PVR_PACKAGE:-df.root}"
PVR_WL="${PVR_WHITELIST_PATH:-/data/system/users/0/pvr_white_list.xml}"
PVR_Q="[\"']"

# Sets PVR_VR and PVR_BOOT: 0 = yes, 1 = no, 2 = no answer.
pvr_snapshot() {
    out=$(timeout 10 dumpsys package "$PVR_PKG" 2>/dev/null | awk -v name="$PVR_PKG.BootReceiver" '
        /isVrApp: true/ { vr = 0 }
        /isVrApp: false/ { vr = 1 }
        /^[[:space:]]*enabledComponents:[[:space:]]*$/ {
            base = index($0, "enabledComponents") - 1
            seen = 1
            section = "on"
            next
        }
        /^[[:space:]]*disabledComponents:[[:space:]]*$/ {
            base = index($0, "disabledComponents") - 1
            seen = 1
            section = "off"
            next
        }
        section != "" {
            if (match($0, /^ */) && RLENGTH > base) {
                if ($1 == name) boot = section
            } else {
                section = ""
            }
            next
        }
        END {
            if (boot == "on") b = 0
            else if (boot == "off" || seen) b = 1
            else b = 2
            print (vr == "" ? 2 : vr), b
        }
    ')
    PVR_VR=${out% *}
    PVR_BOOT=${out#* }
    [ -n "$PVR_VR" ] || PVR_VR=2
    [ -n "$PVR_BOOT" ] || PVR_BOOT=2
}

pvr_whitelisted() {
    [ -f "$PVR_WL" ] || return 1
    pkg=$(printf '%s' "$PVR_PKG" | sed 's/\./[.]/g')
    grep -Eq "packagename[[:space:]]*=[[:space:]]*${PVR_Q}${pkg}${PVR_Q}" "$PVR_WL"
}

pvr_service_running() {
    spid=$(cat "$1" 2>/dev/null || true)
    case "$spid" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ -r "/proc/$spid/cmdline" ] && grep -q 'service.sh' "/proc/$spid/cmdline" 2>/dev/null
}

pvr_attrs() {
    chown system:system "$1" || return 1
    chmod 0644 "$1" || return 1
    restorecon "$1" 2>/dev/null || true
}

# Set the attributes before the rename; the move preserves them.
pvr_replace() {
    pvr_attrs "$1" || { rm -f "$1"; return 1; }
    mv -f "$1" "$PVR_WL" || { rm -f "$1"; return 1; }
}

# Keep a valid empty document: no file leaves the old sets in place.
pvr_empty() {
    tmp="${PVR_WL}.new.$$"
    printf '<?xml version="1.0" encoding="utf-8"?>\n<whitelist-packages>\n</whitelist-packages>\n' > "$tmp" ||
        return 1
    pvr_replace "$tmp"
}

# Drop only our entry; another package's entry survives.
pvr_strip() {
    tmp="${PVR_WL}.rm.$$"
    pkg=$(printf '%s' "$PVR_PKG" | sed 's/\./[.]/g')

    awk -v re="<(ns2:)?item[^>]*packagename[[:space:]]*=[[:space:]]*${PVR_Q}${pkg}${PVR_Q}[^>]*>" '
        {
            gsub(re, "")
            if ($0 ~ /^[[:space:]]*$/) next
            print
        }
    ' "$PVR_WL" > "$tmp" || { rm -f "$tmp"; return 1; }

    if ! grep -Eq '<(ns2:)?whitelist-packages' "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if grep -Eq '<(ns2:)?item' "$tmp"; then
        pvr_replace "$tmp"
    else
        rm -f "$tmp"
        pvr_empty
    fi
}
