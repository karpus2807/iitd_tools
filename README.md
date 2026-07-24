# IITD Lab Ubuntu Setup Tool

Ubuntu aur Debian lab systems ke liye configuration tool — proxy, IITD apt mirror, aur aage aur modules.

## Features

- **Auto OS detection** — Ubuntu (16.04–26.04) aur Debian (10–13) detect karke release codename ke saath kaam karta hai
- **Menu-driven** — interactive module selection
- **Modular architecture** — naya module add karo, menu mein automatically dikhega
- **IITD Repo module** — `/etc/apt/sources.list` mein `repo.iitd.ernet.in`, official `ubuntu.sources` disable

## Supported Operating Systems

### Ubuntu: **16.04 LTS – 26.04 LTS**

Repo config ek hi template se generate hoti hai; sirf release codename (jaise `focal`, `jammy`, `noble`, `resolute`) automatically lag jata hai.

| Version | Codename |
|---------|----------|
| 16.04 LTS | xenial |
| 18.04 LTS | bionic |
| 20.04 LTS | focal |
| 22.04 LTS | jammy |
| 24.04 LTS | noble |
| 26.04 LTS | resolute |

Poore mapping ke liye dekho: `config/ubuntu-codenames.map`

Nayi Ubuntu release aaye to sirf us file mein ek line add karo — alag repo file banane ki zaroorat nahi.

### Debian: **10 – 13**

| Version | Codename |
|---------|----------|
| 10 | buster |
| 11 | bullseye |
| 12 | bookworm |
| 13 | trixie |

Mapping: `config/debian-codenames.map` · Repo template: `config/repos/debian.sources.list.template`

## Startup Warmup (Dependency Check)

Tool start hote hi automatically check karta hai:

1. **OS** — Ubuntu / Debian version + codename
2. **Python** — system `/usr/bin` Python 2/3
3. **APT packages** — `ca-certificates`, `python3` / `python-minimal`
4. **Python stdlib** — `iitd-proxy` ke liye zaroori modules
5. **Tool files** — templates, scripts, modules

### Failsafe mode

Agar dependencies missing hon:

1. **Direct try** — internet + `repo.iitd.ernet.in` check → bina proxy install
2. **Proxy failsafe** — sirf tab jab direct install fail ho → proxy shell → login → install → normal reboot

Proxy shell cancel: type **`exit`**

```bash
iitd-proxy shell    # manually bhi chala sakte ho (no sudo)
```

Required dependencies fixed list: `config/dependencies.list`

## Quick Start

### Pendrive / offline (lab PCs)

Poora folder USB par copy karo, target Ubuntu system par:

```bash
cd /path/to/iitd_tool
bash install-iitd-tool.sh
```

Sudo password ek baar → system install → main menu.

### Git clone

```bash
git clone https://github.com/karpus2807/iitd_tools.git
cd iitd_tools
chmod +x iitd-tool
sudo ./iitd-tool
# Menu → IITD Tool Management → Install tool system-wide
# Phir: sudo iitd-tool
```

## Project Structure

```
iitd_tool/
├── install-iitd-tool.sh     # Pendrive launcher (sudo + install + menu)
├── iitd-config              # Main entry script
├── lib/
│   ├── common.sh            # Logging, backup, utilities
│   ├── detect.sh            # Ubuntu / Debian version detection
│   ├── deps.sh              # Startup dependency check / warmup
│   ├── install.sh           # System-wide install (iitd-tool install)
│   ├── paths.sh             # /var/lib/iitd-tool data directories
│   ├── repo_manage.sh       # Repo submenu actions + restore
│   ├── repos.sh             # Repo template generation
│   ├── tools_install.sh     # Basic tools checkbox installer
│   ├── ssl_fix.sh           # SSL / CA trust repair
│   ├── backups.sh           # Unified backups list / menu helpers
│   ├── updater.sh           # GitHub updater (latest 5)
│   ├── snmp.sh              # SNMP install / config / remove
│   └── modules.sh           # Module discovery & menu
├── iitd-tool                # Entry point (same as iitd-config)
├── config/
│   ├── dependencies.list    # APT packages + tool files manifest
│   ├── basic-tools.list     # Checkbox tool package list
│   ├── backup-targets.list  # Extensible backup registry
│   ├── snmp/
│   │   └── snmpd.conf.template
│   ├── repos/
│   │   └── sources.list.template   # Ubuntu IITD mirror template
│   │   └── debian.sources.list.template
│   └── ubuntu-codenames.map        # Version → codename fallback map
│   └── debian-codenames.map
├── scripts/
│   ├── iitd-proxy                  # Bash launcher (python3/python2 auto-detect)
│   └── iitd-proxy.py               # Proxy logic (Python 2.7 + 3.x compatible)
└── modules/
    ├── system/              # Install / uninstall tool
    │   └── module.sh
    ├── updater/             # GitHub tool update / downgrade
    │   └── module.sh
    ├── backups/             # Backups list + full restore
    │   └── module.sh
    ├── iitd_repo/           # IITD repository setup
    │   └── module.sh
    └── proxy/               # Installs iitd-proxy command (one-time)
        └── module.sh
    └── basic_tools/         # Checkbox installer for common CLI tools
        └── module.sh
    └── ssl_fix/             # Repair CA trust / certificate verify errors
        └── module.sh
    └── snmp/                # snmpd install / config / remove
        └── module.sh
        └── backup_targets.sh
```

## SNMP Setup

Menu **SNMP Setup**:

1. Install from apt (`snmpd`, `snmp`)  
2. Config — prompts **sysLocation** + **sysContact**, writes `/etc/snmp/snmpd.conf` from template  
3. Remove SNMP config  
4. Remove SNMP packages (purge)  

Template defaults: SNMPv2c, `rocommunity cse!005 10.208.20.30`, UDP 161, DMI `extend` lines.  
`snmpd.conf` is registered in Backups & Restore.

## ThingsBoard Telemetry (Raspberry Pi 3 / 4)

Menu **ThingsBoard Telemetry** — MQTT client sends CPU/RAM/disk/IP to ThingsBoard.

1. Install (`tb-mqtt-client` + script + `iitd-thingsboard.service`)  
2. Configure `TB_HOST`, `TB_ACCESS_TOKEN`, interval  
3. Enable & start service  

Pi 3–friendly: safe swap math, eth0/wlan0 MAC preference, interval ≥ 30s, low `Nice` priority.  
Config: `/etc/iitd-thingsboard.conf` · Logs: `journalctl -u iitd-thingsboard -f`

## Adding a New Module

Naya module add karne ke liye `modules/<name>/module.sh` banao:

```bash
#!/usr/bin/env bash

MODULE_ID="my_module"
MODULE_NAME="My Module"
MODULE_DESCRIPTION="Short description shown in menu"
MODULE_ORDER=30          # Lower = higher in menu

module_supported_versions() {
    echo "all"   # ya specific: "20.04 22.04 24.04"
}

module_run() {
    local ubuntu_version="$1"
    local ubuntu_codename="$2"
    # Your setup logic here
}
```

Tool automatically `modules/*/module.sh` files discover karega aur menu mein add karega.

## IITD Repo Module

Submenu — har step alag se chalao:

1. Backup sources.list  
2. Apply IITD mirror (`repo.iitd.ernet.in`)  
3. Disable ubuntu.sources  
4. Disable 3rd party repositories  
5. Run apt update  
6. Restore original repository status  

Backups & restore: `/var/lib/iitd-tool/backups/`

System install: `sudo iitd-tool install` → `/etc/iitd-tool`

## Tool Updater

Menu **Tool Updater** — GitHub (`karpus2807/iitd_tools`) se latest 5 releases/tags/commits dikhata hai.

- Koi bhi entry choose karke upgrade **ya** downgrade  
- Update ke dauran **Do NOT cancel** warning  
- `/etc/iitd-tool` clean + reinstall; `/var/lib/iitd-tool/backups` **preserve**  
- Install ke baad backups list show  

## Backups & Restore

Unified **extensible** menu:

1. Backup all registered targets  
2. Restore all  
3. Backup particular  
4. Restore particular (pick target + snapshot)  
5. List backup files  
6. Show registered targets  

**Add a target (no menu code change):**

```text
# config/backup-targets.list
my.conf|My config|/etc/my.conf|my.conf
```

Or `modules/<name>/backup_targets.sh`:

```bash
backups_register "my.conf" "My config" "/etc/my.conf" "my.conf"
```

## Basic Tools Module

Menu option **Basic Tools Installer** — common CLI tools checkbox list se install karo.

**Controls:**
- Terminal mein: ↑/↓ move, **SPACE** toggle, **ENTER** install, **q** cancel
- Agar `whiptail` available ho to checklist UI use hota hai

**Default tools** (`config/basic-tools.list`): wget, curl, tmux, screen, SSH client/server, net-tools (ifconfig), git, vim, htop, rsync, build-essential, dig/nslookup, ping, tree, nc, ...

Already installed packages list mein `[installed]` dikhte hain; sirf missing packages install hote hain.

## SSL Fix Module

Menu option **SSL Fix** — certificate / TLS trust issues theek karta hai:

1. Legacy custom IITD/CCIITD CA files remove  
2. `ca-certificates` reinstall  
3. `update-ca-certificates --fresh`  
4. System time hint + optional HTTPS test  

Campus pe updates ke liye SSL Fix ke baad proxy ON rakho (`iitd-proxy`).

## Proxy Module

Proxy module **sirf ek baar** admin `sudo iitd-tool` se install karta hai. Uske baad **kisi bhi user** se proxy enable/disable bina `sudo` type kiye.

### Step 1: Install (ek baar, admin / sudo)

```bash
sudo ./iitd-config
# Menu se "Proxy Setup (Install iitd-proxy)" select karo
```

Yeh install karega:
- `/usr/local/bin/iitd-proxy` (launcher — non-root pe auto-elevate)
- `/usr/local/lib/iitd-tool/iitd-proxy.py`
- `/etc/sudoers.d/iitd-proxy` (NOPASSWD — password prompt nahi)
- Dependencies: `python3` ya `python-minimal` (auto-detect) + `ca-certificates`

**Python 2 aur 3 dono supported** — sirf **system Python** use hota hai (`/usr/bin/python3` ya `/usr/bin/python2`). Pyenv, conda, `/usr/local` wale custom Python ignore hote hain.

### Step 2: Proxy enable (kisi bhi user, bina sudo)

```bash
iitd-proxy staff krajaymeena
iitd-proxy phd ankit
iitd-proxy btech USERID
```

Password prompt aayega (IITD kerberos/proxy password — local sudo password nahi).

### Step 3: Proxy hatana (logout)

```bash
iitd-proxy logout
```

Pure system se proxy remove ho jayegi.

### Kya configure hota hai

| Component | Method |
|-----------|--------|
| APT / apt store | `/etc/apt/apt.conf.d/95iitd-proxy` |
| Snap Store | `snap set system proxy.*` |
| Git / GitHub | `git config --system http(s).proxy` + host-specific GitHub proxies |
| Ubuntu GUI (GNOME) | `gsettings` system proxy |
| wget | `~/.wgetrc` |
| curl | `~/.curlrc` |
| Chrome | `/etc/opt/chrome/policies/managed/` |
| Chromium | `/etc/chromium/policies/managed/` |
| Firefox | `/etc/firefox/policies/policies.json` |
| All shell/apps | `/etc/environment`, `/etc/profile.d/`, systemd |

### Roles

| Role | Proxy prefix |
|------|--------------|
| btech | 22 |
| mtech | 62 |
| phd | 61 |
| staff | 78 |
| faculty | 82 |
| visitor | 21 |

Log file: `/var/log/iitd-proxy.log`

## Requirements

- Bash 4+
- Ubuntu 16.04 to 26.04 **or** Debian 10 to 13
- Python 2.7 **or** Python 3.x from `/usr/bin` only (distro-managed; custom installs ignored)
- Root access (sudo) for system configuration modules
