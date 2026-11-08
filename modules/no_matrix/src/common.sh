#!/system/bin/sh

PKG=com.bytedance.pico.matrix
STATE=/data/adb/no_matrix
ORIG=$STATE/orig
PIDFILE=$STATE/service.pid
HOST=setting-global-api
Q='&quot;'

MODDIR=${MODDIR:-${MODPATH:-$(dirname "$0")}}

DATA=
for d in "/data/user/0/$PKG" "/data/data/$PKG"; do
    if [ -d "$d" ]; then
        DATA=$d
        break
    fi
done
DATA=${DATA:-/data/user/0/$PKG}
PREFS=$DATA/shared_prefs
ENT=$PREFS/matrix_entitlement_config_storage.sp.xml
LOCAL=$PREFS/__local_settings_data.sp.xml
TOB=$PREFS/tob_entitlement_config_storage.sp.xml

MAIN_FLAGS="entitlement_check_init_enable entitlement_check_last_step_enable entitlement_check_set_launch_intercept_enable entitlement_check_before_launch_enable entitlement_check_after_launch_enable entitlement_check_when_dev_call_enable entitlement_is_need_check_verify_app_disable check_expiry_before_launch check_expiry_after_launch check_expiry_dev_call kill_app_when_no_cache kill_app_when_cache_not_pass"

TOB_FLAGS="entitlement_check_init_enable entitlement_check_last_step_enable entitlement_check_sign_enable entitlement_check_set_launch_intercept_enable entitlement_check_before_launch_enable entitlement_check_after_launch_enable entitlement_check_when_dev_call_enable check_expiry_before_launch check_expiry_after_launch check_expiry_dev_call"

log() { command log -t no_matrix "$*" 2>/dev/null || true; }

pkg_uid() {
    u=$(stat -c %u "$DATA" 2>/dev/null) || return 1
    case "$u" in
        '' | *[!0-9]*) return 1 ;;
    esac
    echo "$u"
}

matrix_pid() { pidof "$PKG" 2>/dev/null | awk '{print $1; exit}'; }

restart_matrix() {
    old=$(matrix_pid)
    [ -n "$old" ] || return 0
    kill -9 "$old" 2>/dev/null || return 1
    i=0
    while [ "$i" -lt 20 ]; do
        new=$(matrix_pid)
        [ -n "$new" ] && [ "$new" != "$old" ] && return 0
        sleep 0.5
        i=$((i + 1))
    done
    return 1
}

backup() {
    mkdir -p "$ORIG" || return 1
    for f in "$ENT" "$LOCAL" "$TOB"; do
        [ -f "$f" ] || continue
        b=$ORIG/${f##*/}
        [ -f "$b" ] && continue
        cp -a "$f" "$b" 2>/dev/null || cat "$f" > "$b" 2>/dev/null || return 1
    done
    if [ ! -f "$ORIG/intercept" ]; then
        v=$(settings get global ns_intercept_com_bytedance_pico_matrix 2>/dev/null) || v=
        [ -n "$v" ] && printf '%s' "$v" > "$ORIG/intercept"
    fi
    return 0
}

restore_one() {
    b=$1
    f=$2
    if [ ! -f "$b" ]; then
        [ -f "$f" ] && return 1
        return 0
    fi
    if [ -f "$f" ]; then
        cat "$b" > "$f" 2>/dev/null && return 0
    fi
    cp "$b" "$f" 2>/dev/null || return 1
    u=$(pkg_uid) || u=
    [ -n "$u" ] && chown "$u:$u" "$f" 2>/dev/null
    chmod 660 "$f" 2>/dev/null
    command -v restorecon >/dev/null 2>&1 && restorecon "$f" 2>/dev/null
    return 0
}

restore() {
    ok=1
    restore_one "$ORIG/${ENT##*/}" "$ENT" || ok=0
    restore_one "$ORIG/${LOCAL##*/}" "$LOCAL" || ok=0
    restore_one "$ORIG/${TOB##*/}" "$TOB" || ok=0
    [ "$ok" = 1 ]
}

intercept_clear() {
    settings delete global ns_intercept_com_bytedance_pico_matrix >/dev/null 2>&1 || true
}

intercept_ok() {
    v=$(settings get global ns_intercept_com_bytedance_pico_matrix 2>/dev/null)
    [ -z "$v" ] || [ "$v" = null ]
}

intercept_restore() {
    [ -f "$ORIG/intercept" ] || {
        intercept_clear
        return 0
    }
    v=$(cat "$ORIG/intercept" 2>/dev/null)
    if [ "$v" = null ] || [ -z "$v" ]; then
        intercept_clear
    else
        settings put global ns_intercept_com_bytedance_pico_matrix "$v" >/dev/null 2>&1
    fi
}

rule_add() {
    u=$(pkg_uid) || return 1
    set -- -p tcp --dport 443 -m owner --uid-owner "$u" -m string --string "$HOST" --algo bm -j DROP
    ok=0
    for cmd in iptables ip6tables; do
        command -v "$cmd" >/dev/null 2>&1 || continue
        "$cmd" -w 5 -C OUTPUT "$@" 2>/dev/null && ok=1 && continue
        "$cmd" -w 5 -I OUTPUT "$@" 2>/dev/null && ok=1
    done
    [ "$ok" = 1 ]
}

rule_del() {
    u=$(pkg_uid) || return 1
    set -- -p tcp --dport 443 -m owner --uid-owner "$u" -m string --string "$HOST" --algo bm -j DROP
    for cmd in iptables ip6tables; do
        command -v "$cmd" >/dev/null 2>&1 || continue
        while "$cmd" -w 5 -C OUTPUT "$@" 2>/dev/null; do
            "$cmd" -w 5 -D OUTPUT "$@" 2>/dev/null || break
        done
    done
}

rule_ok() {
    u=$(pkg_uid) || return 1
    command -v iptables >/dev/null 2>&1 || return 0
    set -- -p tcp --dport 443 -m owner --uid-owner "$u" -m string --string "$HOST" --algo bm -j DROP
    iptables -w 5 -C OUTPUT "$@" 2>/dev/null
}

patch_one() {
    f=$1
    mode=$2
    [ -f "$f" ] || return 0
    tmp=$STATE/patch.$$
    awk -v mode="$mode" -f "$MODDIR/patch.awk" "$f" > "$tmp" 2>/dev/null || {
        rm -f "$tmp"
        return 1
    }
    if cmp -s "$tmp" "$f"; then
        rm -f "$tmp"
        return 0
    fi
    cat "$tmp" > "$f" 2>/dev/null || {
        rm -f "$tmp"
        return 1
    }
    rm -f "$tmp"
}

patch() {
    mkdir -p "$STATE" 2>/dev/null
    patch_one "$ENT" main || return 1
    patch_one "$LOCAL" local || return 1
    patch_one "$TOB" tob || return 1
    return 0
}

key_false() { grep -Eq "$Q$1$Q[[:space:]]*:[[:space:]]*false" "$2"; }
key_true() { grep -Eq "$Q$1$Q[[:space:]]*:[[:space:]]*true" "$2"; }
key_empty() { grep -Eq "$Q$1$Q[[:space:]]*:[[:space:]]*$2" "$3"; }
key_release() { grep -Eq "$Q$1$Q[[:space:]]*:[[:space:]]*\[[^]]*$Q""release$Q" "$2"; }

prefs_ok() {
    [ -f "$ENT" ] || return 1
    for k in $MAIN_FLAGS; do
        key_false "$k" "$ENT" || return 1
    done
    key_empty black_list_of_pkg '\[\]' "$ENT" || return 1
    key_empty black_list_of_pkg_sign '\{\}' "$ENT" || return 1
    key_empty toc_business_black_list_of_pkg '\[\]' "$ENT" || return 1
    key_empty toc_business_black_list_of_pkg_sign '\{\}' "$ENT" || return 1
    key_release skip_login_check_build_type_scope "$ENT" || return 1
    key_true skip_login_check_by_2d "$ENT" || return 1
    if [ -f "$TOB" ]; then
        for k in $TOB_FLAGS; do
            key_false "$k" "$TOB" || return 1
        done
    fi
    return 0
}

verify() { rule_ok && prefs_ok && intercept_ok; }

apply() {
    backup || {
        log "backup failed"
        return 1
    }
    n=0
    while [ "$n" -lt 3 ]; do
        rule_add || log "rule failed"
        intercept_clear
        patch || {
            log "patch failed"
            return 1
        }
        restart_matrix
        intercept_clear
        verify && return 0
        n=$((n + 1))
        [ "$n" -lt 3 ] && sleep 2
    done
    return 1
}

wait_boot() {
    i=0
    while [ "$(getprop sys.boot_completed)" != 1 ] && [ "$i" -lt 90 ]; do
        sleep 2
        i=$((i + 1))
    done
}
