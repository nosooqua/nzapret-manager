# nzapret-manager

Ubuntu-native manager for [bol-van/zapret](https://github.com/bol-van/zapret) — a DPI bypass daemon. Inspired by [Zapret-Manager](https://github.com/StressOzz/Zapret-Manager) (OpenWRT) and [zapret.installer](https://github.com/Snowy-Fluffy/zapret.installer).

## What it does

- Installs the upstream `bol-van/zapret` (clone + build) under `/opt/zapret`
- Manages `zapret.service` via systemd (start / stop / enable / disable)
- Ships a catalog of strategies:
  - **v1..v9** — general-purpose nfqws configs ported from Zapret-Manager
  - **Yv01..Yv100+** — YouTube/Flowseal catalog fetched on demand
  - **Dv1..Dv17** — Discord-media strategies
- Auto-tests strategies in parallel via curl against a configurable URL list and ranks them
- Toggles named `/etc/hosts` blocks (Instagram, Telegram Web, AI services, Rutracker…) with marker-bounded sections (clean enable / disable)
- Lets you add your own `/etc/hosts` blocks, override shipped ones, edit the test-URL catalog, and edit zapret's per-user include / exclude / ipban lists (`zapret-hosts-user*.txt`)
- Configures DNS-over-HTTPS via `dnscrypt-proxy` with curated presets (Cloudflare, Google, Quad9, AdGuard, Comss, Xbox, dns.malw.link, dns.mafioznik.xyz, dns.astracat.ru, dns.nullsproxy.com) and points `systemd-resolved` at it
- Backs up and restores `/opt/zapret/config`, the systemd unit, the active hosts blocks, the DoH config, and the upstream zapret per-user lists

podkop and OpenWRT-specific features are intentionally out of scope.

## Install

Tested on Ubuntu 22.04 / 24.04.

```sh
sudo bash install.sh               # deploy nzapret-manager under /opt/nzapret-manager, install deps
sudo nzapret-manager install       # clone + build bol-van/zapret, enable systemd unit
sudo nzapret-manager               # open the TUI
```

One-shot via curl:

```sh
curl -fsSL https://raw.githubusercontent.com/nosooqua/nzapret-manager/main/install.sh | sudo bash
```

## CLI quick reference

```
nzapret-manager                          open TUI
nzapret-manager install | update | uninstall
nzapret-manager list [builtin|youtube|discord|all]
nzapret-manager preview <id>
nzapret-manager apply   <id>             id ∈ v1..v9 | Yv01..Yv100+ | Dv1..Dv17
nzapret-manager current
nzapret-manager test    [general|youtube|discord|all]
nzapret-manager fetch-youtube            (re)fetch Yv* catalog
nzapret-manager hosts   <enable|disable|list|disable-all|create|edit|delete> [name]
nzapret-manager test-urls edit           edit your test-URL overlay
nzapret-manager zapret-list <user|exclude|ipban> edit
nzapret-manager doh     <list|apply <id>|disable|remove|status|test>
nzapret-manager service <start|stop|restart|enable|disable|status|log>
nzapret-manager backup  <create|list|restore <file>|prune [N]>
```

## Custom lists

User-defined data lives under `/etc/nzapret-manager/` and is preserved across re-installs:

| Path | Purpose |
| --- | --- |
| `/etc/nzapret-manager/hosts.d/<name>.hosts` | Your own `/etc/hosts` blocks. A user copy with the same name overrides the shipped one. |
| `/etc/nzapret-manager/test-urls.user.txt`   | Extra rows appended to the shipped `data/test-urls.txt` during auto-test. |
| `/opt/zapret/ipset/zapret-hosts-user.txt`   | Upstream zapret include list (domains to apply DPI bypass to). |
| `/opt/zapret/ipset/zapret-hosts-user-exclude.txt` | Upstream zapret exclude list. |
| `/opt/zapret/ipset/zapret-hosts-user-ipban.txt`   | Upstream zapret IP-ban list. |

All of the above can be edited via `nzapret-manager` → *Custom lists* (menu 4), or from the CLI:

```sh
sudo nzapret-manager hosts create mysite      # create + open in $EDITOR
sudo nzapret-manager hosts edit ai-services   # copies shipped block into hosts.d/ on first edit
sudo nzapret-manager test-urls edit
sudo nzapret-manager zapret-list user edit
```

## DNS over HTTPS

`nzapret-manager` configures `dnscrypt-proxy` (apt) bound on `127.0.2.1:53` and writes a `systemd-resolved` drop-in at `/etc/systemd/resolved.conf.d/nzapret-manager.conf` so all system DNS goes through the chosen DoH endpoint.

```sh
sudo nzapret-manager doh list                 # show preset IDs
sudo nzapret-manager doh apply cloudflare     # or: google, quad9, adguard, comss, xbox, malw, mafioznik, astracat, nullsproxy …
sudo nzapret-manager doh test                 # query example.com via current resolver
sudo nzapret-manager doh disable              # stop the proxy, restore default resolved
sudo nzapret-manager doh remove               # purge dnscrypt-proxy entirely
```

Providers from the upstream DNSCrypt `public-resolvers.md` catalog are selected by their canonical name; the rest are declared as `[static]` entries with sdns:// stamps computed on the fly from their DoH URL.

## Layout

| Path | Owner | Purpose |
| --- | --- | --- |
| `/opt/nzapret-manager/` | this project | code + data |
| `/opt/zapret/` | `bol-van/zapret` | binaries (`nfqws`, `tpws`), upstream config |
| `/etc/systemd/system/zapret.service` | this project | systemd unit |
| `/etc/nzapret-manager/state` | this project | active strategy, hosts toggles, current DoH preset |
| `/etc/nzapret-manager/hosts.d/` | user | custom hosts fragments (preserved across re-installs) |
| `/etc/nzapret-manager/test-urls.user.txt` | user | extra rows for the auto-test catalog |
| `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` | this project | DoH provider config (when enabled) |
| `/etc/systemd/resolved.conf.d/nzapret-manager.conf` | this project | resolved → dnscrypt-proxy drop-in |
| `/var/log/nzapret-manager/` | this project | auto-test CSVs, build logs |
| `/var/backups/nzapret-manager/` | this project | tar.gz snapshots |

## Uninstall

```sh
sudo bash /opt/nzapret-manager/uninstall.sh
```

Backups in `/var/backups/nzapret-manager/` are kept so a re-install can restore.

## Credits

Strategy bodies and `/etc/hosts` blocks ported from [StressOzz/Zapret-Manager](https://github.com/StressOzz/Zapret-Manager). YouTube `ListStrYou` is fetched directly from the same upstream.
