#!/usr/bin/env bash
# Tear down zapretozz: remove the zapret daemon, the systemd unit, the
# /opt/zapretozz checkout, the CLI symlink, /etc/zapretozz state, and any
# /etc/hosts blocks we added.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "uninstall.sh must run as root (use sudo)" >&2
    exit 1
fi

INSTALL_DIR="/opt/zapretozz"
BIN_LINK="/usr/local/bin/zapretozz"

if [[ -x "${INSTALL_DIR}/zapretozz" ]]; then
    "${INSTALL_DIR}/zapretozz" hosts disable-all 2>/dev/null || true
    "${INSTALL_DIR}/zapretozz" uninstall            2>/dev/null || true
fi

rm -f  "$BIN_LINK"
rm -rf "$INSTALL_DIR"
rm -rf /etc/zapretozz
rm -rf /var/log/zapretozz

echo "[+] zapretozz removed. Backups in /var/backups/zapretozz left intact."
