#!/usr/bin/env bash
# Install apt dependencies required to build and run bol-van/zapret.

DEPS_BASE=(git curl ca-certificates jq tar gzip python3)
DEPS_BUILD=(build-essential pkg-config libnetfilter-queue-dev libmnl-dev libcap-dev libcap2-bin zlib1g-dev)
DEPS_RUNTIME=(iptables nftables ipset)

deps_apt_update_done=0

deps_apt_update() {
    if [[ $deps_apt_update_done -eq 0 ]]; then
        info "apt update"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq || warn "apt-get update returned non-zero (continuing)"
        deps_apt_update_done=1
    fi
}

deps_install() {
    require_root
    local missing=()
    local pkg
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi
    deps_apt_update
    info "Installing: ${missing[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" \
        || die "apt-get install failed for: ${missing[*]}"
}

deps_install_all() {
    deps_install "${DEPS_BASE[@]}" "${DEPS_BUILD[@]}" "${DEPS_RUNTIME[@]}"
}

deps_install_minimal() {
    deps_install "${DEPS_BASE[@]}"
}
