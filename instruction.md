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

Admin **ek baar** install kare (`sudo iitd-tool` → Proxy Setup).  
Uske baad **kisi bhi user** se (bina sudo password):

```bash
iitd-proxy <role> <userid>    # login / enable
iitd-proxy logout             # logout
iitd-proxy shell              # interactive
```

Backend root ke liye `/etc/sudoers.d/iitd-proxy` (NOPASSWD) lagta hai — user ko `sudo` type nahi karna padta.

**TLS:** koi custom certificate nahi — pehle system CA, fail ho to verify-off fallback.

### `6` — Basic Tools Installer

Checkbox list se tools chun kar install karo:

- ↑/↓ move · **SPACE** toggle · **ENTER** install · **q** cancel  
- (whiptail available ho to woh UI use hota hai)

**Tools list:** wget, curl, tmux, ssh, ssh server, ifconfig (net-tools), git, vim, htop, rsync, build-essential, ...  
→ `config/basic-tools.list`

### `7` — SSL Fix

Certificate / TLS issues theek karo (Ubuntu 18 upgrade pe common):

1. Custom IITD/CCIITD CA files hatao  
2. `ca-certificates` reinstall  
3. `update-ca-certificates --fresh`  
4. Time check + HTTPS test  

Phir campus pe: `iitd-proxy <role> <userid>` → `apt update` / `do-release-upgrade`

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

### `9` — ThingsBoard Telemetry (Pi 3 / Pi 4)

Raspberry Pi (ya lab PC) se MQTT telemetry → ThingsBoard.

| # | Option |
|---|--------|
| 1 | Install client (`tb-mqtt-client` + script + systemd) |
| 2 | Configure host / **ACCESS_TOKEN** / interval |
| 3 | Enable & start `iitd-thingsboard` service |
| 4 | Stop service |
| 5 | Status |
| 6 | Remove |
| b | Back |

Config: `/etc/iitd-thingsboard.conf` · Service: `iitd-thingsboard`  
Pi 3: interval **≥ 30s** recommended. Backup target registered.

### `q` — Quit

---

## Proxy commands (menu 3 ke baad)

```bash
iitd-proxy <role> <userid>    # proxy ON  (no sudo)
iitd-proxy logout             # proxy OFF
iitd-proxy shell              # interactive (exit to quit)
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
| 2026-07-23 | ThingsBoard Telemetry module (Pi 3/4 MQTT client + systemd) |
| 2026-07-15 | SNMP Setup menu (install/config/remove + snmpd.conf backup) |
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
