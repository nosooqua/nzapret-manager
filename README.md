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
- Backs up and restores `/opt/zapret/config`, the systemd unit, and the active hosts blocks

DNSSEC, podkop, DoH, and OpenWRT-specific features are intentionally out of scope.

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
nzapret-manager hosts   <enable|disable|list|disable-all> [name]
nzapret-manager service <start|stop|restart|enable|disable|status|log>
nzapret-manager backup  <create|list|restore <file>|prune [N]>
```

## Layout

| Path | Owner | Purpose |
| --- | --- | --- |
| `/opt/nzapret-manager/` | this project | code + data |
| `/opt/zapret/` | `bol-van/zapret` | binaries (`nfqws`, `tpws`), upstream config |
| `/etc/systemd/system/zapret.service` | this project | systemd unit |
| `/etc/nzapret-manager/state` | this project | active strategy, hosts toggles |
| `/var/log/nzapret-manager/` | this project | auto-test CSVs, build logs |
| `/var/backups/nzapret-manager/` | this project | tar.gz snapshots |

## Uninstall

```sh
sudo bash /opt/nzapret-manager/uninstall.sh
```

Backups in `/var/backups/nzapret-manager/` are kept so a re-install can restore.

## Credits

Strategy bodies and `/etc/hosts` blocks ported from [StressOzz/Zapret-Manager](https://github.com/StressOzz/Zapret-Manager). YouTube `ListStrYou` is fetched directly from the same upstream.
