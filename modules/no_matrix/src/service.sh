#!/system/bin/sh

MODDIR=$(dirname "$0")
. "$MODDIR/common.sh"

if [ -f "$PIDFILE" ]; then
    old=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null &&
        grep -q 'service\.sh' "/proc/$old/cmdline" 2>/dev/null; then
        exit 0
    fi
fi

mkdir -p "$STATE"
echo $$ > "$PIDFILE"
trap '[ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"' 0

wait_boot
log "starting"
if apply; then
    log "active"
else
    log "apply incomplete"
fi

while sleep 60; do
    if ! verify; then
        log "state changed, reapplying"
        apply || log "reapply incomplete"
    fi
done
