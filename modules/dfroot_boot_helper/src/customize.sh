#!/system/bin/sh

. "$MODPATH/common.sh"

pm path "$PVR_PKG" >/dev/null 2>&1 || abort "! Install DFRoot first"
pvr_snapshot
[ "$PVR_BOOT" = 0 ] || abort "! Enable \"Start root on boot\" in DFRoot first"

sh "$MODPATH/apply.sh" || abort "! Failed to write the Pico VR whitelist entry"

ui_print "- Whitelisted $PVR_PKG for boot start"
ui_print "- Reboot to apply"
