# IITD Lab Setup Tool — Instructions

> Project change hone par yahi file update karo.  
> Repo: https://github.com/karpus2807/iitd_tools

Ubuntu **16.04 – 26.04** aur Debian **10 – 13** lab systems ke liye — IITD repo + proxy setup.

---

## Pehli baar (sirf ek baar manually)

### Option A — Pendrive (recommended for lab PCs)

Poora `iitd_tool` folder USB mein copy karo, phir target system par:

```bash
cd /media/usb/iitd_tool    # apna pendrive path
bash install-iitd-tool.sh
```

- Ek baar **sudo password** puchega  
- Tool **system-wide install** ho jayega (`/etc/iitd-tool`)  
- Phir **main menu** khul jayega  

### Option B — Git clone

```bash
git clone https://github.com/karpus2807/iitd_tools.git
cd iitd_tools
chmod +x iitd-config iitd-tool
sudo ./iitd-tool
```

Menu se **IITD Tool Management → Install tool system-wide** chun lo.  
Uske baad hamesha: `sudo iitd-tool` (kahi se bhi)

---

## Main menu (`sudo iitd-tool`)

Startup: System · Python · Dependencies · Data path

### `1` — IITD Tool Management

| # | Option | Kya karta hai |
|---|--------|---------------|
| 1 | Install tool system-wide | `/etc/iitd-tool` + `iitd-tool` command |
| 2 | Uninstall tool | System se tool hatao (data optional) |
| 3 | Show install status | Installed hai ya nahi |
| b | Back | Main menu |

### `2` — Tool Updater

GitHub se latest **5 updates** (commits / releases) dikhao — upgrade **ya** downgrade.

- Select karke install  
- Warning: **Do NOT cancel** during update  
- Purane tool files clean; **backups preserve** (`/var/lib/iitd-tool/backups`)  
- Install ke baad preserved backups list dikhegi  

Campus pe pehle: `iitd-proxy <role> <userid>` (GitHub download ke liye)

### `3` — Backups & Restore

Extensible menu (`config/backup-targets.list` se naye targets add karo):

| # | Option |
|---|--------|
| 1 | **Backup all** registered targets |
| 2 | **Restore all** backed-up files & config |
| 3 | **Backup particular** file / config |
| 4 | **Restore particular** file / config (original ya koi .bak) |
| 5 | List backup files |
| 6 | Show registered targets |
| b | Back |

Extend: line add in `config/backup-targets.list` **ya** `modules/<name>/backup_targets.sh`

### `4` — IITD Repository Setup (submenu)

| # | Option |
|---|--------|
| 1 | Apply IITD mirror |
| 2 | Disable ubuntu.sources / debian.sources |
| 3 | Disable 3rd party repos |
| 4 | Run apt update |
| b | Back |

(Backup/Restore ab **Backups & Restore** menu mein hain)

### `5` — Proxy Setup (Install iitd-proxy)

Admin **ek baar** CLI install kare (`sudo iitd-tool` → Proxy Setup).

```bash
iitd-proxy <role> <userid>    # any user, no root — login + user-session
iitd-proxy logout
iitd-proxy shell
```

**System-wide** apt/snap/docker/browsers: `sudo iitd-tool` startup pe **staff** userid + password (no sudoers / NOPASSWD).

**TLS:** verified by default. Prefer SSL → Install Certificate (`ca-chain`). Optional: `IITD_PROXY_INSECURE_TLS=1`.

**Proxy covers (system-wide):** apt, snap, **docker** (daemon + client), git/GitHub, GNOME, wget/curl, Chrome/Chromium/Firefox.

### `6` — Basic Tools Installer

Checkbox list se tools chun kar install karo:

- ↑/↓ move · **SPACE** toggle · **ENTER** install · **q** cancel  
- (whiptail available ho to woh UI use hota hai)

**Tools list:** wget, curl, tmux, ssh, ssh server, ifconfig (net-tools), git, vim, htop, rsync, build-essential, ...  
→ `config/basic-tools.list`

### `7` — SSL / Certificates

Submenu:

1. **Install Certificate** — `config/certs/ca-chain.crt` (GlobalSign) system pe install
2. **Update Certificate** — ca-chain refresh
3. **Remove Certificate** — IITD ca-chain (optional: sab local custom CAs) + official sync
4. **Certificate Status**
5. **SSL Fix** — CCIITD leftovers hatao, `ca-certificates` reinstall, trust refresh, ca-chain re-apply

### `8` — SNMP Setup

| # | Option |
|---|--------|
| 1 | Install SNMP from apt (`snmpd` + `snmp`) |
| 2 | Config SNMP — prompts **sysLocation** + **sysContact**, writes `/etc/snmp/snmpd.conf` |
| 3 | Remove SNMP config (restore original / package default) |
| 4 | Remove SNMP tool (purge packages) |
| b | Back |

Fixed in template: SNMPv2c, community `cse!005`, monitor `10.208.20.30`, UDP 161, DMI extends.  
Backup target: `snmpd.conf` → Backups & Restore menu.

### `q` — Quit

---

## Proxy commands

```bash
sudo iitd-tool                 # staff login → system-wide proxy
iitd-proxy <role> <userid>     # any user, no root
iitd-proxy logout
iitd-proxy shell
```

**Roles:** `btech` · `mtech` · `phd` · `staff` · `faculty` · `visitor`

---

## Data directory

| Path | Purpose |
|------|---------|
| `/var/lib/iitd-tool/backups/` | Repo backups |
| `/var/lib/iitd-tool/state/` | Restore manifest |
| `/etc/iitd-tool/` | Installed tool |

---

## Dependencies missing (startup)

**Step 1:** Direct install (internet + IITD repo)  
**Step 2:** Proxy failsafe → login → install

Cancel: **`exit`**

---

## Change log

| Date | Update |
|------|--------|
| 2026-09-15 | iitd-proxy: skip staff login at tool start if proxy already configured; `status` / `check-active` |
| 2026-09-15 | iitd-proxy: Docker daemon + client proxy (systemd drop-in + ~/.docker/config.json) |
| 2026-07-24 | iitd-proxy: Git/GitHub system proxy (with snap) for clone/API/assets |
| 2026-07-23 | ThingsBoard Telemetry module (Pi 3/4 MQTT client + systemd) |
| 2026-07-15 | SNMP Setup menu (install/config/remove + snmpd.conf backup) |
| 2026-08-08 | Remove ThingsBoard; proxy without sudoers; staff login at iitd-tool start; ca-chain SSL menu; atomic updater |
| 2026-08-08 | SSL menu: Install/Update `ca-chain.crt` (GlobalSign) into system trust |
| 2026-07-15 | Backups: extensible targets (all + particular backup/restore) |
| 2026-07-15 | Tool Updater + Backups & Restore menus (GitHub updates / unified restore) |
| 2026-07-15 | iitd-proxy: any user login/logout without typing sudo (sudoers) |
| 2026-07-13 | SSL Fix menu — repair CA trust / certificate errors |
| 2026-07-09 | Portable launcher `install-iitd-tool.sh` (pendrive install) |
| 2026-07-10 | Proxy TLS: custom CA removed, verify-off fallback only |
| 2026-07-10 | Debian 10–13 OS support added (Ubuntu + Debian) |
| 2026-07-09 | Direct install before proxy failsafe |

---

*Har change ke baad change log update karo.*
