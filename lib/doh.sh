#!/usr/bin/env bash
# DoH (DNS-over-HTTPS) setup via dnscrypt-proxy.
#
# The active provider is selected from a curated preset list (see _doh_presets).
# For providers in the upstream DNSCrypt public-resolvers catalog we just pass
# their canonical name via `server_names`; for the rest we declare a `[static]`
# entry with a precomputed sdns:// stamp. dnscrypt-proxy is configured to bind
# 127.0.2.1:53, and systemd-resolved is pointed at it via a drop-in.

DOH_PROXY_SERVICE="dnscrypt-proxy.service"
DOH_LISTEN="127.0.2.1:53"

#
# Preset registry: each line is `id|label|kind|payload`.
#   kind=named    payload=<canonical name from public-resolvers.md>
#   kind=static   payload=<DoH URL: https://host[:port]/path>
#
_doh_presets() {
    cat <<'PRESETS'
cloudflare|Cloudflare DNS|named|cloudflare
cloudflare-security|Cloudflare for Malware|named|cloudflare-security
cloudflare-family|Cloudflare for Families|named|cloudflare-family
google|Google Public DNS|named|google
quad9|Quad9 (filter + DNSSEC)|named|quad9-doh-ip4-port443-filter-pri
adguard|AdGuard DNS|named|adguard-dns-doh
adguard-family|AdGuard Family Protection|named|adguard-dns-family-doh
comss|Comss.one DNS|static|https://dns.comss.one/dns-query
xbox|Xbox DNS|static|https://xbox-dns.ru/dns-query
malw|dns.malw.link|static|https://dns.malw.link/dns-query
malw-cf|dns.malw.link (Cloudflare)|static|https://5u35p8m9i7.cloudflare-gateway.com/dns-query
mafioznik|dns.mafioznik.xyz|static|https://dns.mafioznik.xyz/dns-query
astracat|dns.astracat.ru|static|https://dns.astracat.ru/dns-query
nullsproxy|dns.nullsproxy.com (Supercell)|static|https://dns.nullsproxy.com/dns-query
PRESETS
}

doh_preset_ids() { _doh_presets | cut -d'|' -f1; }

doh_preset_lookup() {
    # Args: <id>   Prints: id|label|kind|payload  (returns 1 if not found)
    local want="$1" line
    while IFS= read -r line; do
        [[ ${line%%|*} == "$want" ]] && { printf '%s\n' "$line"; return 0; }
    done < <(_doh_presets)
    return 1
}

doh_is_installed() {
    dpkg -s dnscrypt-proxy >/dev/null 2>&1
}

doh_is_active() {
    systemctl is-active --quiet "$DOH_PROXY_SERVICE"
}

doh_current() {
    state_get DOH_PROVIDER 2>/dev/null || true
}

doh_status_line() {
    if ! doh_is_installed; then
        printf '%snot installed%s' "$C_GRAY" "$C_RESET"; return
    fi
    if doh_is_active; then
        local cur; cur=$(doh_current)
        printf '%sactive%s (%s)' "$C_GREEN" "$C_RESET" "${cur:-?}"
    else
        printf '%sinactive%s' "$C_YELLOW" "$C_RESET"
    fi
}

#
# Compute a DoH (protocol 0x02) DNS stamp from a URL.
# Args: <url>  → echoes "sdns://..."
#
_doh_stamp_from_url() {
    local url="$1"
    command -v python3 >/dev/null 2>&1 || die "python3 is required to build DNS stamps (apt install python3)"
    python3 - "$url" <<'PY'
import base64, sys, urllib.parse as up
u = up.urlsplit(sys.argv[1])
if u.scheme != 'https': sys.exit(f"DoH URL must be https://: {sys.argv[1]}")
host = u.hostname
if u.port: host = f"{host}:{u.port}"
path = u.path or '/dns-query'
b = bytearray()
b.append(0x02)                  # protocol: DoH
b += b"\x00" * 8                # props: 0
b.append(0x00)                  # addr len 0 (empty)
b.append(0x00)                  # hashes: empty list
h = host.encode(); b.append(len(h)); b += h
p = path.encode(); b.append(len(p)); b += p
print("sdns://" + base64.urlsafe_b64encode(bytes(b)).rstrip(b'=').decode())
PY
}

#
# Build /etc/dnscrypt-proxy/dnscrypt-proxy.toml for the chosen preset.
#
_doh_write_config() {
    local id="$1" kind="$2" payload="$3"
    install -d -m 0755 "$(dirname "$DOH_CONFIG")"
    local tmp; tmp=$(mktemp)
    {
        printf '# Managed by nzapret-manager. Do not edit by hand;\n'
        printf '# changes are overwritten on next preset selection.\n'
        printf 'listen_addresses = [%s]\n' "'${DOH_LISTEN}'"
        if [[ $kind == named ]]; then
            printf "server_names = ['%s']\n" "$payload"
        else
            printf "server_names = ['%s']\n" "$id"
        fi
        cat <<'TOML'
require_dnssec = false
require_nolog = false
require_nofilter = false
ipv4_servers = true
ipv6_servers = false
dnscrypt_servers = false
doh_servers = true
odoh_servers = false
require_dnssec_servers = false
cache = true
cache_size = 4096
cache_min_ttl = 600
cache_max_ttl = 86400
cache_neg_min_ttl = 60
cache_neg_max_ttl = 600
fallback_resolvers = ['1.1.1.1:53', '9.9.9.9:53']
ignore_system_dns = true
netprobe_timeout = 60
netprobe_address = '1.1.1.1:53'

[sources]
  [sources.'public-resolvers']
  urls = [
    'https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md',
    'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md',
  ]
  cache_file = '/var/cache/dnscrypt-proxy/public-resolvers.md'
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  refresh_delay = 73
TOML
        if [[ $kind == static ]]; then
            local stamp; stamp=$(_doh_stamp_from_url "$payload")
            printf '\n[static]\n  [static.%s]\n  stamp = %s\n' "'$id'" "'$stamp'"
        fi
    } >"$tmp"
    install -m 0644 "$tmp" "$DOH_CONFIG"
    rm -f "$tmp"
}

_doh_write_resolved_dropin() {
    install -d -m 0755 "$(dirname "$DOH_RESOLVED_DROPIN")"
    cat >"$DOH_RESOLVED_DROPIN" <<EOF
# Managed by nzapret-manager — points systemd-resolved at dnscrypt-proxy.
[Resolve]
DNS=${DOH_LISTEN%:*}
FallbackDNS=
DNSStubListener=yes
EOF
    chmod 0644 "$DOH_RESOLVED_DROPIN"
}

_doh_remove_resolved_dropin() {
    rm -f "$DOH_RESOLVED_DROPIN"
}

doh_install() {
    require_root
    deps_install dnscrypt-proxy python3
    # Newer Ubuntu releases install dnscrypt-proxy with the service masked
    # (because it would clash with stub :53). We explicitly listen on 127.0.2.1.
    systemctl unmask "$DOH_PROXY_SERVICE" 2>/dev/null || true
    install -d -m 0755 /var/cache/dnscrypt-proxy
}

doh_apply_preset() {
    require_root
    local id="$1"
    local row; row=$(doh_preset_lookup "$id") || die "Unknown DoH preset: $id"
    local label kind payload
    IFS='|' read -r _ label kind payload <<<"$row"
    doh_install
    info "Configuring DoH provider: $label"
    _doh_write_config "$id" "$kind" "$payload"
    _doh_write_resolved_dropin
    systemctl enable "$DOH_PROXY_SERVICE" >/dev/null 2>&1 || true
    systemctl restart "$DOH_PROXY_SERVICE" || warn "$DOH_PROXY_SERVICE failed to restart; check: journalctl -u $DOH_PROXY_SERVICE"
    systemctl restart systemd-resolved 2>/dev/null || true
    state_set DOH_PROVIDER "$id"
    ok "DoH active: $label ($id)"
}

doh_disable() {
    require_root
    if doh_is_installed; then
        systemctl stop    "$DOH_PROXY_SERVICE" 2>/dev/null || true
        systemctl disable "$DOH_PROXY_SERVICE" 2>/dev/null || true
    fi
    _doh_remove_resolved_dropin
    systemctl restart systemd-resolved 2>/dev/null || true
    state_unset DOH_PROVIDER
    ok "DoH disabled; systemd-resolved restored to default."
}

doh_remove() {
    require_root
    doh_disable
    if doh_is_installed; then
        info "Removing dnscrypt-proxy"
        DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge dnscrypt-proxy >/dev/null 2>&1 || \
            warn "apt remove failed; remove manually with: apt purge dnscrypt-proxy"
    fi
    ok "DoH stack removed."
}

doh_test_resolver() {
    if command -v resolvectl >/dev/null 2>&1; then
        info "Querying via systemd-resolved:"
        resolvectl query example.com 2>&1 | sed 's/^/  /'
    else
        info "Querying via dig:"
        dig +short example.com 2>&1 | sed 's/^/  /' || warn "dig not available"
    fi
}

doh_list_presets() {
    printf '  %-18s %-22s %s\n' "ID" "TYPE" "LABEL"
    local id label kind payload
    while IFS='|' read -r id label kind payload; do
        printf '  %-18s %-22s %s\n' "$id" "$kind" "$label"
    done < <(_doh_presets)
}
