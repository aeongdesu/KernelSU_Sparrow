#!/system/bin/sh

MODDIR=$(dirname "$0")
. "$MODDIR/common.sh"

if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        i=0
        while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do
            sleep 0.2
            i=$((i + 1))
        done
        kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$PIDFILE"
fi

rule_del
intercept_clear

if restore; then
    intercept_restore
    restart_matrix
    rm -rf "$STATE"
    log "original matrix settings restored"
else
    intercept_restore
    restart_matrix
    log "backup incomplete, kept at $STATE"
fi
