# zapretozz-ubuntu

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
sudo bash install.sh         # deploy zapretozz under /opt/zapretozz, install deps
sudo zapretozz install       # clone + build bol-van/zapret, enable systemd unit
sudo zapretozz               # open the TUI
```

One-shot via curl:

```sh
curl -fsSL https://raw.githubusercontent.com/nosooqua/nzapret-manager/main/install.sh | sudo bash
```

## CLI quick reference

```
zapretozz                          open TUI
zapretozz install | update | uninstall
zapretozz list [builtin|youtube|discord|all]
zapretozz preview <id>
zapretozz apply   <id>             id ∈ v1..v9 | Yv01..Yv100+ | Dv1..Dv17
zapretozz current
zapretozz test    [general|youtube|discord|all]
zapretozz fetch-youtube            (re)fetch Yv* catalog
zapretozz hosts   <enable|disable|list|disable-all> [name]
zapretozz service <start|stop|restart|enable|disable|status|log>
zapretozz backup  <create|list|restore <file>|prune [N]>
```

## Layout

| Path | Owner | Purpose |
| --- | --- | --- |
| `/opt/zapretozz/` | this project | code + data |
| `/opt/zapret/` | `bol-van/zapret` | binaries (`nfqws`, `tpws`), upstream config |
| `/etc/systemd/system/zapret.service` | this project | systemd unit |
| `/etc/zapretozz/state` | this project | active strategy, hosts toggles |
| `/var/log/zapretozz/` | this project | auto-test CSVs, build logs |
| `/var/backups/zapretozz/` | this project | tar.gz snapshots |

## Uninstall

```sh
sudo bash /opt/zapretozz/uninstall.sh
```

Backups in `/var/backups/zapretozz/` are kept so a re-install can restore.

## Credits

Strategy bodies and `/etc/hosts` blocks ported from [StressOzz/Zapret-Manager](https://github.com/StressOzz/Zapret-Manager). YouTube `ListStrYou` is fetched directly from the same upstream.
