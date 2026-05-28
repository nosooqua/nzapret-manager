#!/usr/bin/env bash
# Common helpers, paths, and styling shared across all nzapret-manager modules.

set -o pipefail

NZAPRET_MANAGER_DIR="${NZAPRET_MANAGER_DIR:-/opt/nzapret-manager}"
ZAPRET_DIR="${ZAPRET_DIR:-/opt/zapret}"
ZAPRET_REPO="${ZAPRET_REPO:-https://github.com/bol-van/zapret.git}"
ZAPRET_UNIT="/etc/systemd/system/zapret.service"
ZAPRET_CONFIG="${ZAPRET_DIR}/config"

STATE_DIR="/etc/nzapret-manager"
STATE_FILE="${STATE_DIR}/state"
LOG_DIR="/var/log/nzapret-manager"
BACKUP_DIR="/var/backups/nzapret-manager"
DATA_DIR="${NZAPRET_MANAGER_DIR}/data"
STRATEGY_DIR="${DATA_DIR}/strategies"
HOSTS_FRAGMENT_DIR="${DATA_DIR}/hosts"
YT_STRATEGY_URL="${YT_STRATEGY_URL:-https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/ListStrYou}"

STRATEGY_BEGIN="# === nzapret-manager strategy begin ==="
STRATEGY_END="# === nzapret-manager strategy end ==="
HOSTS_MARKER_PREFIX="# === nzapret-manager:"

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[1;31m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[1;34m'
    C_MAGENTA=$'\033[1;35m'
    C_CYAN=$'\033[1;36m'
    C_GRAY=$'\033[38;5;244m'
else
    C_RESET='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_MAGENTA='' C_CYAN='' C_GRAY=''
fi

info()  { printf '%s[*]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()    { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()   { err "$*"; exit 1; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This action requires root. Re-run with sudo."
    fi
}

require_ubuntu() {
    [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release; not a supported system."
    . /etc/os-release
    case "${ID:-}:${ID_LIKE:-}" in
        ubuntu:*|*:*ubuntu*|*:*debian*) : ;;
        debian:*)                       : ;;
        *) die "Unsupported distribution: ${PRETTY_NAME:-unknown}. This tool targets Ubuntu/Debian." ;;
    esac
}

pause() {
    printf '%sPress Enter to continue...%s' "$C_GRAY" "$C_RESET"
    read -r _ || true
}

ensure_dirs() {
    install -d -m 0755 "$STATE_DIR" "$LOG_DIR" "$BACKUP_DIR"
}

state_get() {
    local key="$1"
    [[ -r $STATE_FILE ]] || return 1
    awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/, ""); print; exit }' "$STATE_FILE"
}

state_set() {
    local key="$1" val="$2"
    ensure_dirs
    touch "$STATE_FILE"
    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        local tmp; tmp=$(mktemp)
        awk -F= -v k="$key" -v v="$val" 'BEGIN{OFS="="} $1==k {$0=k"="v} {print}' "$STATE_FILE" >"$tmp"
        mv "$tmp" "$STATE_FILE"
    else
        printf '%s=%s\n' "$key" "$val" >>"$STATE_FILE"
    fi
}

state_unset() {
    local key="$1"
    [[ -f $STATE_FILE ]] || return 0
    sed -i.bak "/^${key}=/d" "$STATE_FILE" && rm -f "${STATE_FILE}.bak"
}

header() {
    local title="$1"
    local width=48
    local pad=$(( (width - ${#title}) / 2 ))
    printf '%s' "$C_CYAN"
    printf '╔'; printf '═%.0s' $(seq 1 $width); printf '╗\n'
    printf '║%*s%s%*s║\n' "$pad" "" "$title" "$(( width - pad - ${#title} ))" ""
    printf '╚'; printf '═%.0s' $(seq 1 $width); printf '╝'
    printf '%s\n' "$C_RESET"
}
