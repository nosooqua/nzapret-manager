#!/usr/bin/env bash
# Marker-delimited /etc/hosts block manager.
#
# A "block" is a named fragment in data/hosts/<name>.hosts. Enabling a block
# appends its content to /etc/hosts wrapped between markers:
#
#   # === zapretozz:<name> begin ===
#   <fragment>
#   # === zapretozz:<name> end ===
#
# Disabling removes the lines between (and including) the markers. The marker
# scheme guarantees idempotent enable/disable with no leftover state.

HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"

hosts_blocks_available() {
    [[ -d $HOSTS_FRAGMENT_DIR ]] || return 0
    local f
    for f in "$HOSTS_FRAGMENT_DIR"/*.hosts; do
        [[ -e $f ]] || continue
        basename "$f" .hosts
    done | sort
}

hosts_block_enabled() {
    local name="$1"
    grep -qF "${HOSTS_MARKER_PREFIX}${name} begin" "$HOSTS_FILE" 2>/dev/null
}

hosts_label_for() {
    local name="$1"
    local f="${HOSTS_FRAGMENT_DIR}/${name}.hosts"
    [[ -r $f ]] || return 1
    awk '/^[[:space:]]*#/ { sub(/^[[:space:]]*#[[:space:]]*/, ""); print; exit }' "$f"
}

hosts_enable() {
    require_root
    local name="$1"
    local frag="${HOSTS_FRAGMENT_DIR}/${name}.hosts"
    [[ -f $frag ]] || die "No such hosts block: $name"
    if hosts_block_enabled "$name"; then
        info "Block already enabled: $name (refreshing)"
        hosts_disable "$name" >/dev/null
    fi
    {
        printf '%s%s begin ===\n' "$HOSTS_MARKER_PREFIX" "$name"
        cat "$frag"
        printf '%s%s end ===\n' "$HOSTS_MARKER_PREFIX" "$name"
    } >>"$HOSTS_FILE"
    _hosts_refresh_resolver
    state_set "HOSTS_$(_norm "$name")" 1
    ok "Enabled hosts block: $name"
}

hosts_disable() {
    require_root
    local name="$1"
    local tmp; tmp=$(mktemp)
    awk -v B="${HOSTS_MARKER_PREFIX}${name} begin" \
        -v E="${HOSTS_MARKER_PREFIX}${name} end" '
        $0 ~ B { skip = 1; next }
        $0 ~ E { skip = 0; next }
        !skip   { print }
    ' "$HOSTS_FILE" >"$tmp"
    install -m 0644 "$tmp" "$HOSTS_FILE"
    rm -f "$tmp"
    _hosts_refresh_resolver
    state_unset "HOSTS_$(_norm "$name")"
    ok "Disabled hosts block: $name"
}

hosts_disable_all() {
    require_root
    local b
    for b in $(hosts_blocks_available); do
        hosts_block_enabled "$b" && hosts_disable "$b" >/dev/null
    done
}

_norm() { tr '[:lower:]-' '[:upper:]_' <<<"$1"; }

_hosts_refresh_resolver() {
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches >/dev/null 2>&1 || true
    elif systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        systemctl restart systemd-resolved >/dev/null 2>&1 || true
    fi
}
