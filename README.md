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
2. **Proxy failsafe** — staff proxy login → install → normal restart

Tool start pe hamesha **staff userid + password** maangta hai (system-wide proxy).

```bash
sudo iitd-tool              # root required; staff proxy at startup
iitd-proxy staff USERID     # any user, no root — user-session proxy / re-login
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
    └── ssl_fix/             # Install/update/remove CA + SSL Fix
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

Submenu:

1. Apply IITD mirror (`repo.iitd.ernet.in`)  
2. Disable official / 3rd-party sources as needed  
3. Update apt  

Backups & restore: unified **Backups & Restore** menu (`/var/lib/iitd-tool/backups/`).

System install: `sudo iitd-tool install` → `/etc/iitd-tool`

## Tool Updater

Menu **Tool Updater** — GitHub (`karpus2807/iitd_tools`) se latest 5 releases/tags/commits dikhata hai.

- Koi bhi entry choose karke upgrade **ya** downgrade  
- Update ke dauran **Do NOT cancel** warning  
- Atomic staging swap into `/etc/iitd-tool`; `/var/lib/iitd-tool/backups` **preserve**  
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

## SSL / Certificates Module

Menu option **SSL / Certificates**:

1. **Install Certificate** — bundled `config/certs/ca-chain.crt` (GlobalSign chain) system trust store mein install  
2. **Update Certificate** — same ca-chain refresh / overwrite  
3. **Remove Certificate** — IITD ca-chain + local/custom CAs hatao, official Ubuntu/Debian `ca-certificates` se sync  
4. **Certificate Status** — installed vs bundled cert details  
5. **SSL Fix** — legacy CCIITD CA hatao, `ca-certificates` reinstall, trust refresh, phir ca-chain re-apply  

Install paths:
- `/usr/local/share/ca-certificates/iitd-ca-chain-NN.crt`
- `/usr/local/lib/iitd-tool/certs/ca-chain.crt`

Campus pe updates ke liye SSL Fix / cert install ke baad proxy ON rakho (`iitd-proxy`).

## Proxy Module

**Design:**
- `sudo iitd-tool` — root required; startup pe **staff** userid + password → system-wide proxy (apt, snap, docker, browsers, …)
- `iitd-proxy` — **kisi bhi user**, **bina root/sudo**; IITD login + user-session settings. No passwordless sudoers.

### Step 1: Install CLI (optional, admin)

```bash
sudo iitd-tool
# Menu → Proxy Setup (Install iitd-proxy)
```

Installs:
- `/usr/local/bin/iitd-proxy` (no auto-sudo)
- `/usr/local/lib/iitd-tool/iitd-proxy.py`
- Removes legacy `/etc/sudoers.d/iitd-proxy` if present
- `python3` / `python-minimal` + `ca-certificates`

### Step 2: Daily use

```bash
sudo iitd-tool                 # staff login → system-wide
iitd-proxy staff USERID        # any user: login + user-session
iitd-proxy logout              # user-session clear (system clear only if root)
```

TLS verified by default. Only if needed: `IITD_PROXY_INSECURE_TLS=1`. Prefer SSL menu → Install Certificate (`ca-chain`).

### What system-wide mode configures (root / iitd-tool)

| Component | Method |
|-----------|--------|
| APT | `/etc/apt/apt.conf.d/95iitd-proxy` |
| Snap | `snap set system proxy.*` |
| Docker | daemon: `/etc/systemd/system/docker.service.d/http-proxy.conf` · client: `~/.docker/config.json` |
| Git / GitHub | system + user git proxy |
| GNOME | gsettings |
| Chrome / Chromium / Firefox | managed policies |
| Shell/apps | `/etc/environment`, profile.d, systemd |

### Roles

| Role | Proxy prefix |
|------|--------------|
| btech | 22 |
| mtech | 62 |
| phd | 61 |
| staff | 78 |
| faculty | 82 |
| visitor | 21 |

## Requirements

- Bash 4+
- Ubuntu 16.04 to 26.04 **or** Debian 10 to 13
- Python 2.7 **or** Python 3.x from `/usr/bin` only (distro-managed; custom installs ignored)
- Root (`sudo iitd-tool`) for admin tool + system-wide proxy
