#!/usr/bin/env bash
# User-editable list management:
#   - custom /etc/hosts fragments under /etc/nzapret-manager/hosts.d/
#   - custom test URL overlay at /etc/nzapret-manager/test-urls.user.txt
#   - upstream zapret per-user lists at /opt/zapret/ipset/zapret-hosts-user*.txt
#
# Each helper opens the file in $EDITOR and, where the change affects a running
# service, restarts it after save. Block / list names are validated against the
# same character set the hosts marker scheme expects: [A-Za-z0-9._-].

_validate_block_name() {
    local n="$1"
    [[ $n =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid name '$n' (allowed: A-Z a-z 0-9 . _ -)"
    [[ ${#n} -le 40 ]]            || die "Name too long (max 40)"
}

custom_hosts_list() {
    ensure_dirs
    local f name label src state
    while IFS= read -r name; do
        [[ -z $name ]] && continue
        if hosts_is_user_block "$name"; then src="user"; else src="shipped"; fi
        state="-"; hosts_block_enabled "$name" && state="+"
        label=$(hosts_label_for "$name" 2>/dev/null || true)
        printf '%s %-7s %-22s %s\n' "$state" "$src" "$name" "${label:-}"
    done < <(hosts_blocks_available)
}

custom_hosts_create() {
    require_root
    ensure_dirs
    local name="${1:-}"
    if [[ -z $name ]]; then
        name=$(prompt "New block name: ")
    fi
    _validate_block_name "$name"
    local f="${USER_HOSTS_DIR}/${name}.hosts"
    if [[ -e $f ]]; then
        warn "Already exists: $f"
    else
        cat >"$f" <<EOF
# ${name} — user-defined block
# One entry per line:  <IP>  <host1> [host2 ...]
# Example:
#   45.155.204.190 example.com www.example.com
EOF
        chmod 0644 "$f"
        ok "Created $f"
    fi
    open_editor "$f"
    if hosts_block_enabled "$name"; then
        info "Re-applying enabled block to /etc/hosts"
        hosts_enable "$name" >/dev/null
    fi
}

custom_hosts_edit() {
    require_root
    ensure_dirs
    local name="${1:-}"
    [[ -n $name ]] || die "Usage: hosts edit <name>"
    if [[ -f ${USER_HOSTS_DIR}/${name}.hosts ]]; then
        : # already user-owned
    elif [[ -f ${HOSTS_FRAGMENT_DIR}/${name}.hosts ]]; then
        info "Copying shipped '${name}' into ${USER_HOSTS_DIR}/ for editing (user copy overrides shipped)"
        install -m 0644 "${HOSTS_FRAGMENT_DIR}/${name}.hosts" "${USER_HOSTS_DIR}/${name}.hosts"
    else
        die "No such block: $name"
    fi
    open_editor "${USER_HOSTS_DIR}/${name}.hosts"
    if hosts_block_enabled "$name"; then
        info "Re-applying block to /etc/hosts"
        hosts_enable "$name" >/dev/null
    fi
}

custom_hosts_delete() {
    require_root
    ensure_dirs
    local name="${1:-}"
    [[ -n $name ]] || die "Usage: hosts delete <name>"
    [[ -f ${USER_HOSTS_DIR}/${name}.hosts ]] || die "Not a user block: $name"
    if hosts_block_enabled "$name"; then
        hosts_disable "$name" >/dev/null
    fi
    rm -f -- "${USER_HOSTS_DIR}/${name}.hosts"
    ok "Removed user block: $name"
}

custom_test_urls_edit() {
    require_root
    ensure_dirs
    if [[ ! -f $USER_TEST_URLS ]]; then
        cat >"$USER_TEST_URLS" <<'EOF'
# User-defined URLs appended to the bundled test catalog.
# Format:  <scope>  <url>
# Scope tags: general | youtube | discord | ai
# Lines starting with '#' are ignored.
#
# Example:
#   general  https://example.com/
#   youtube  https://www.youtube.com/watch?v=dQw4w9WgXcQ
EOF
        chmod 0644 "$USER_TEST_URLS"
    fi
    open_editor "$USER_TEST_URLS"
}

_zapret_user_list_path() {
    case "$1" in
        user|include) printf '%s\n' "$ZAPRET_USER_LIST" ;;
        exclude)      printf '%s\n' "$ZAPRET_USER_EXCLUDE" ;;
        ipban)        printf '%s\n' "$ZAPRET_USER_IPBAN" ;;
        *) return 1 ;;
    esac
}

custom_zapret_list_edit() {
    require_root
    local kind="${1:-}"
    local f; f=$(_zapret_user_list_path "$kind") || die "Usage: zapret-list edit <user|exclude|ipban>"
    zapret_is_installed || die "zapret is not installed."
    install -d -m 0755 "$(dirname "$f")"
    [[ -f $f ]] || { : >"$f"; chmod 0644 "$f"; }
    open_editor "$f"
    if service_exists && service_is_active; then
        info "Restarting zapret.service to pick up the new list"
        systemctl restart "$SERVICE_NAME" || warn "Service restart failed."
    fi
}
