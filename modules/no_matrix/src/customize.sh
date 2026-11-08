#!/system/bin/sh

. "$MODPATH/common.sh"

pm path "$PKG" >/dev/null 2>&1 || abort "! matrix not installed"

backup || ui_print "! could not back up Matrix settings :("

if apply; then
    ui_print "- goodbye matrix!"
else
    ui_print "! apply incomplete, will retry on boot"
fi
