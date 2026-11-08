BEGIN {
    Q = "&quot;"
    R = "\\&quot;"
    insert = (mode != "local")
}

# R is Q escaped for gsub replacements (awk expands & in replacements)
function setbool(key, val) {
    if (!gsub(Q key Q "[ \t\r\n]*:[ \t\r\n]*(true|false)", R key R ":" val, s) && insert && index(s, Q key Q) == 0)
        add(key, val)
}

function setarr(key, val, plain) {
    if (!gsub(Q key Q "[ \t\r\n]*:[ \t\r\n]*\\[[^]]*\\]", R key R ":" val, s) && insert && index(s, Q key Q) == 0)
        add(key, plain == "" ? val : plain)
}

function setobj(key, val) {
    if (!gsub(Q key Q "[ \t\r\n]*:[ \t\r\n]*\\{[^}]*\\}", R key R ":" val, s) && insert && index(s, Q key Q) == 0)
        add(key, val)
}

function add(key, val,    e, j, c, prefix) {
    e = index(s, "</string>")
    if (!e) return
    j = e - 1
    while (j > 0 && substr(s, j, 1) != "}") j--
    if (!j) return
    c = j - 1
    while (c > 0 && substr(s, c, 1) ~ /[ \t\r\n]/) c--
    prefix = (substr(s, c, 1) == "{" || substr(s, c, 1) == ",") ? "" : ","
    s = substr(s, 1, c) prefix Q key Q ":" val substr(s, c + 1)
}

{ s = s $0 "\n" }

END {
    if (mode == "tob") {
        setbool("entitlement_check_init_enable", "false")
        setbool("entitlement_check_last_step_enable", "false")
        setbool("entitlement_check_sign_enable", "false")
        setbool("entitlement_check_set_launch_intercept_enable", "false")
        setbool("entitlement_check_before_launch_enable", "false")
        setbool("entitlement_check_after_launch_enable", "false")
        setbool("entitlement_check_when_dev_call_enable", "false")
        setbool("check_expiry_before_launch", "false")
        setbool("check_expiry_after_launch", "false")
        setbool("check_expiry_dev_call", "false")
    } else {
        setbool("entitlement_check_init_enable", "false")
        setbool("entitlement_check_last_step_enable", "false")
        setbool("entitlement_check_set_launch_intercept_enable", "false")
        setbool("entitlement_check_before_launch_enable", "false")
        setbool("entitlement_check_after_launch_enable", "false")
        setbool("entitlement_check_when_dev_call_enable", "false")
        setbool("entitlement_is_need_check_verify_app_disable", "false")
        setbool("check_expiry_before_launch", "false")
        setbool("check_expiry_after_launch", "false")
        setbool("check_expiry_dev_call", "false")
        setbool("kill_app_when_no_cache", "false")
        setbool("kill_app_when_cache_not_pass", "false")
        setarr("black_list_of_pkg", "[]")
        setobj("black_list_of_pkg_sign", "{}")
        setarr("toc_business_black_list_of_pkg", "[]")
        setobj("toc_business_black_list_of_pkg_sign", "{}")
        setarr("skip_login_check_build_type_scope", "[" R "debug" R "," R "release" R "]", "[" Q "debug" Q "," Q "release" Q "]")
        setbool("skip_login_check_by_2d", "true")
    }
    printf "%s", s
}
