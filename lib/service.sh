#!/usr/bin/env bash
# Thin wrappers around `systemctl` for the zapret.service unit.

SERVICE_NAME="zapret.service"

service_exists() {
    systemctl list-unit-files --type=service 2>/dev/null | awk '{print $1}' | grep -qx "$SERVICE_NAME"
}

service_is_active() {
    systemctl is-active --quiet "$SERVICE_NAME"
}

service_is_enabled() {
    systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null
}

service_start()   { require_root; systemctl start   "$SERVICE_NAME"; }
service_stop()    { require_root; systemctl stop    "$SERVICE_NAME"; }
service_restart() { require_root; systemctl restart "$SERVICE_NAME"; }
service_enable()  { require_root; systemctl enable  "$SERVICE_NAME"; }
service_disable() { require_root; systemctl disable "$SERVICE_NAME"; }

service_status_line() {
    if ! service_exists; then
        printf '%sNot installed%s' "$C_GRAY" "$C_RESET"
        return
    fi
    if service_is_active; then
        printf '%sactive%s' "$C_GREEN" "$C_RESET"
    else
        printf '%sinactive%s' "$C_RED" "$C_RESET"
    fi
    printf ' / '
    if service_is_enabled; then
        printf '%senabled%s' "$C_GREEN" "$C_RESET"
    else
        printf '%sdisabled%s' "$C_YELLOW" "$C_RESET"
    fi
}

service_show_status() {
    if ! service_exists; then
        warn "zapret.service is not installed yet."
        return 1
    fi
    systemctl --no-pager status "$SERVICE_NAME" || true
}

service_tail_log() {
    journalctl -u "$SERVICE_NAME" --no-pager -n "${1:-100}"
}
