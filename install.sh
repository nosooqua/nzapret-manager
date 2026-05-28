#!/usr/bin/env bash
# Bootstrap installer: deploys nzapret-manager into /opt/nzapret-manager and links the CLI.
#
# Usage:
#   sudo bash install.sh                 # deploy from this checkout
#   curl -fsSL <raw>/install.sh | sudo bash    # one-liner (clones origin into /opt/nzapret-manager)
#
# After bootstrap, use `nzapret-manager` to install/configure the zapret daemon.

set -euo pipefail

REPO_URL_DEFAULT="https://github.com/nosooqua/nzapret-manager.git"   # override with NZAPRET_MANAGER_REPO=...
INSTALL_DIR="/opt/nzapret-manager"
BIN_LINK="/usr/local/bin/nzapret-manager"

if [[ $EUID -ne 0 ]]; then
    echo "install.sh must run as root (use sudo)" >&2
    exit 1
fi

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}:${ID_LIKE:-}" in
        ubuntu:*|debian:*|*:*ubuntu*|*:*debian*) : ;;
        *) echo "Unsupported distro: ${PRETTY_NAME:-unknown}. Targets Ubuntu/Debian." >&2; exit 1 ;;
    esac
fi

echo "[*] apt update && installing base tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends git curl ca-certificates

SCRIPT_SRC="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SRC" && -f "$SCRIPT_SRC" ]]; then
    SCRIPT_DIR=$(cd -- "$(dirname -- "$SCRIPT_SRC")" && pwd)
else
    SCRIPT_DIR=""
fi

if [[ -n "$SCRIPT_DIR" && -f "${SCRIPT_DIR}/nzapret-manager" && -d "${SCRIPT_DIR}/lib" ]]; then
    echo "[*] Deploying local checkout from ${SCRIPT_DIR} to ${INSTALL_DIR}"
    if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR"
        cp -a "${SCRIPT_DIR}/." "${INSTALL_DIR}/"
    fi
else
    REPO_URL="${NZAPRET_MANAGER_REPO:-$REPO_URL_DEFAULT}"
    echo "[*] Cloning ${REPO_URL} into ${INSTALL_DIR}"
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        git -C "$INSTALL_DIR" fetch --depth=1 origin
        git -C "$INSTALL_DIR" reset --hard origin/HEAD
    else
        rm -rf "$INSTALL_DIR"
        git clone --depth=1 "$REPO_URL" "$INSTALL_DIR"
    fi
fi

chmod +x "${INSTALL_DIR}/nzapret-manager" 2>/dev/null || true
find "${INSTALL_DIR}/lib" -name '*.sh' -exec chmod +x {} +

ln -sfn "${INSTALL_DIR}/nzapret-manager" "$BIN_LINK"

echo "[+] nzapret-manager bootstrapped."
echo "    Next step:  sudo nzapret-manager install        # build & enable the zapret daemon"
echo "    Or just:    sudo nzapret-manager                # open the TUI"
