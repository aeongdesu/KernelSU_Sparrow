#!/system/bin/sh
set -u

MODDIR=$(dirname "$0")
URI="content://com.pico.settings/whitelist"
PIDFILE="$MODDIR/service.pid"

. "$MODDIR/common.sh"

log_t() {
    command log -t dfroot_boot_helper "$*" 2>/dev/null || true
}

# app_process needs init's mount namespace to link libnativeloader.so.
NS="busybox nsenter -t 1 -m"
$NS true >/dev/null 2>&1 || NS=

apk_path() {
    timeout 20 $NS pm path "$PVR_PKG" 2>/dev/null | sed -n 's/^package://p' | head -n 1
}

notify_observer() {
    $NS env CLASSPATH="$MODDIR/notify.dex" app_process /system/bin Notify "$URI" >/dev/null 2>&1
}

restore_whitelist() {
    case "$PVR_BOOT" in
        1) pvr_empty && log_t "boot start disabled, whitelist left empty" ;;
        # an unknown state keeps the entry: without it the next boot loses root
        *) sh "$MODDIR/apply.sh" >/dev/null 2>&1 && log_t "whitelist restored for next boot" ;;
    esac
}

wait_for_system_server() {
    last=
    stable=0
    tries=0
    while [ "$stable" -lt 4 ] && [ "$tries" -lt 24 ]; do
        tries=$((tries + 1))
        pid=$(pidof system_server 2>/dev/null | awk '{ print $1; exit }')
        pvr_snapshot
        if [ -n "$pid" ] && [ "$pid" = "$last" ] && [ "$PVR_VR" -ne 2 ]; then
            stable=$((stable + 1))
        else
            stable=0
        fi
        last=$pid
        sleep 5
    done
    log_t "system_server settled (pid $last, checks $tries)"
}

# Read only at parse time: drop the entry, notify, then reparse.
clean_vr() {
    deadline=$(($(date +%s) + 300))
    attempt=1
    while [ "$(date +%s)" -lt "$deadline" ]; do
        pvr_empty
        if notify_observer; then
            apk=$(apk_path)
            if [ -n "$apk" ] && timeout 180 $NS pm install -r -d "$apk" >/dev/null 2>&1; then
                sleep 2
                pvr_snapshot
                if [ "$PVR_VR" -eq 1 ]; then
                    log_t "$PVR_PKG reparsed as non-VR"
                    return 0
                fi
            fi
        else
            log_t "notify unavailable (attempt $attempt)"
        fi
        log_t "cleanup attempt $attempt failed"
        attempt=$((attempt + 1))
        sleep 5
    done
    return 1
}

sync_switch() {
    case "$PVR_BOOT" in
        0) pvr_whitelisted ||
            { sh "$MODDIR/apply.sh" >/dev/null 2>&1 && log_t "boot start enabled, whitelist restored"; } ;;
        1) pvr_whitelisted &&
            { pvr_empty && log_t "boot start disabled, whitelist removed"; } ;;
    esac
}

if pvr_service_running "$PIDFILE"; then
    log_t "already running"
    exit 0
fi
echo $$ > "$PIDFILE"
trap '[ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"' 0

log_t "starting"
wait_for_system_server

case "$PVR_VR" in
    0) clean_vr || log_t "cleanup failed" ;;
    1) log_t "already non-VR" ;;
    *) log_t "package state unknown" ;;
esac
restore_whitelist

# VR state and the boot switch only exist in dumpsys, so poll it.
while :; do
    sleep 10
    [ "$(cat "$PIDFILE" 2>/dev/null || true)" = "$$" ] || exit 0
    pvr_snapshot
    case "$PVR_VR" in
        0)
            log_t "VR flag appeared, cleaning"
            clean_vr || log_t "cleanup failed"
            restore_whitelist
            ;;
        1) sync_switch ;;
    esac
done
