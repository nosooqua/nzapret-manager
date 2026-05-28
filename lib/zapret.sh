#!/usr/bin/env bash
# Install / update / remove the bol-van/zapret upstream tree, and own the systemd unit.

zapret_is_installed() {
    [[ -x "${ZAPRET_DIR}/binaries/my/nfqws" ]] || [[ -x "${ZAPRET_DIR}/nfq/nfqws" ]]
}

zapret_clone() {
    require_root
    deps_install_all
    install -d -m 0755 "$(dirname "$ZAPRET_DIR")"
    if [[ -d "${ZAPRET_DIR}/.git" ]]; then
        info "Updating ${ZAPRET_DIR} from origin"
        git -C "$ZAPRET_DIR" fetch --depth=1 origin || die "git fetch failed"
        git -C "$ZAPRET_DIR" reset --hard origin/HEAD || die "git reset failed"
    else
        info "Cloning ${ZAPRET_REPO} into ${ZAPRET_DIR}"
        rm -rf "$ZAPRET_DIR"
        git clone --depth=1 "$ZAPRET_REPO" "$ZAPRET_DIR" || die "git clone failed"
    fi
}

zapret_build() {
    require_root
    info "Building zapret (make -C ${ZAPRET_DIR})"
    if ! make -C "$ZAPRET_DIR" >/var/log/zapretozz/build.log 2>&1; then
        err "Build failed. See /var/log/zapretozz/build.log"
        return 1
    fi
    ok "Build complete"
}

zapret_write_default_config() {
    # Create a minimal /opt/zapret/config if none exists, so the init script can boot.
    # Strategy bodies are inserted later by strategies_apply().
    [[ -f $ZAPRET_CONFIG ]] && return 0
    info "Writing default ${ZAPRET_CONFIG}"
    cat >"$ZAPRET_CONFIG" <<'CFG'
# Minimal zapret config managed by zapretozz.
# The block between the markers below is rewritten by `zapretozz apply <id>`.

FWTYPE=iptables
MODE=nfqws
MODE_HTTP=1
MODE_HTTPS=1
MODE_QUIC=1
INIT_APPLY_FW=1

NFQWS_PORTS_TCP=80,443
NFQWS_PORTS_UDP=443,50000-50100,19294-19344
NFQWS_TCP_PKT_OUT=9
NFQWS_TCP_PKT_IN=3
NFQWS_UDP_PKT_OUT=9

# === zapretozz strategy begin ===
NFQWS_OPT="--dpi-desync=fake,split2"
# === zapretozz strategy end ===
CFG
    chmod 0644 "$ZAPRET_CONFIG"
}

zapret_write_unit() {
    require_root
    info "Writing ${ZAPRET_UNIT}"
    cat >"$ZAPRET_UNIT" <<UNIT
[Unit]
Description=zapret DPI bypass daemon (managed by zapretozz)
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
EnvironmentFile=-${ZAPRET_CONFIG}
ExecStart=${ZAPRET_DIR}/init.d/sysv/zapret start
ExecStop=${ZAPRET_DIR}/init.d/sysv/zapret stop
ExecReload=${ZAPRET_DIR}/init.d/sysv/zapret restart
Restart=on-failure
RestartSec=5
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
}

zapret_install() {
    require_root
    ensure_dirs
    zapret_clone
    zapret_build || return 1
    zapret_write_default_config
    zapret_write_unit
    systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
    if ! systemctl start "$SERVICE_NAME"; then
        warn "zapret.service failed to start. Check: journalctl -u $SERVICE_NAME -n 80"
        return 1
    fi
    state_set ZAPRET_INSTALLED 1
    state_set ZAPRET_COMMIT "$(git -C "$ZAPRET_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    ok "zapret installed and running."
}

zapret_update() {
    require_root
    zapret_is_installed || die "zapret is not installed yet — run: zapretozz install"
    zapret_clone
    make -C "$ZAPRET_DIR" clean >/dev/null 2>&1 || true
    zapret_build || return 1
    systemctl restart "$SERVICE_NAME" || warn "Service restart failed."
    state_set ZAPRET_COMMIT "$(git -C "$ZAPRET_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    ok "zapret updated."
}

zapret_remove() {
    require_root
    if service_exists; then
        systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    fi
    rm -f "$ZAPRET_UNIT"
    systemctl daemon-reload
    rm -rf "$ZAPRET_DIR"
    state_unset ZAPRET_INSTALLED
    state_unset ZAPRET_COMMIT
    state_unset ACTIVE_STRATEGY
    ok "zapret removed."
}

zapret_print_versions() {
    if zapret_is_installed; then
        local commit; commit=$(git -C "$ZAPRET_DIR" rev-parse --short HEAD 2>/dev/null || echo "?")
        printf 'zapret commit: %s\n' "$commit"
    else
        printf 'zapret: not installed\n'
    fi
}
