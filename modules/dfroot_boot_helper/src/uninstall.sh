#!/system/bin/sh
set -u

MODDIR=$(dirname "$0")
PIDFILE="$MODDIR/service.pid"

. "$MODDIR/common.sh"

pvr_service_running "$PIDFILE" && kill "$(cat "$PIDFILE")" 2>/dev/null
rm -f "$PIDFILE"

if pvr_whitelisted; then
    pvr_unlist && echo "removed $PVR_PKG from $PVR_WL"
fi
