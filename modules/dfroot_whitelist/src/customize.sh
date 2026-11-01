#!/system/bin/sh
export PVR_WHITELIST_PATH PVR_PACKAGE PVR_TYPE

ui_print "- Please check \"Start on boot\" is toggled on in DFRoot app"

sh "$MODPATH/apply.sh" || abort "! Failed to write the Pico VR whitelist entry"

ui_print "- DFRoot is now whitelisted as a Pico VR app"
ui_print "- Full reboot for check"
