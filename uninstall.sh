#!/usr/bin/env bash
# Tear down nzapret-manager: remove the zapret daemon, the systemd unit, the
# /opt/nzapret-manager checkout, the CLI symlink, /etc/nzapret-manager state, and any
# /etc/hosts blocks we added.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "uninstall.sh must run as root (use sudo)" >&2
    exit 1
fi

INSTALL_DIR="/opt/nzapret-manager"
BIN_LINK="/usr/local/bin/nzapret-manager"

if [[ -x "${INSTALL_DIR}/nzapret-manager" ]]; then
    "${INSTALL_DIR}/nzapret-manager" hosts disable-all 2>/dev/null || true
    "${INSTALL_DIR}/nzapret-manager" uninstall            2>/dev/null || true
fi

rm -f  "$BIN_LINK"
rm -rf "$INSTALL_DIR"
rm -rf /etc/nzapret-manager
rm -rf /var/log/nzapret-manager

echo "[+] nzapret-manager removed. Backups in /var/backups/nzapret-manager left intact."
