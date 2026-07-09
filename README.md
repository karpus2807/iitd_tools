# IITD Lab Ubuntu Setup Tool

Ubuntu lab systems (16.04 se 26.04 tak) ke liye configuration tool — proxy, IITD apt mirror, aur aage aur modules.

## Features

- **Auto Ubuntu detection** — version detect karke release codename ke saath kaam karta hai
- **Menu-driven** — interactive module selection
- **Modular architecture** — naya module add karo, menu mein automatically dikhega
- **IITD Repo module** — `/etc/apt/sources.list` mein `repo.iitd.ernet.in`, official `ubuntu.sources` disable

## Supported Ubuntu Versions

**16.04 LTS se 26.04 LTS tak** — koi bhi Ubuntu version is range mein kaam karega.

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

## Startup Warmup (Dependency Check)

Tool start hote hi automatically check karta hai:

1. **OS** — Ubuntu version + codename
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
sudo iitd-proxy shell    # manually bhi chala sakte ho
```

Required dependencies fixed list: `config/dependencies.list`

## Quick Start

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
├── iitd-config              # Main entry script
├── lib/
│   ├── common.sh            # Logging, backup, utilities
│   ├── detect.sh            # Ubuntu version detection (16.04–26.04)
│   ├── deps.sh              # Startup dependency check / warmup
│   ├── install.sh           # System-wide install (iitd-tool install)
│   ├── paths.sh             # /var/lib/iitd-tool data directories
│   ├── repo_manage.sh       # Repo submenu actions + restore
│   ├── repos.sh             # Repo template generation
│   └── modules.sh           # Module discovery & menu
├── iitd-tool                # Entry point (same as iitd-config)
├── config/
│   ├── dependencies.list    # APT packages + tool files manifest
│   ├── repos/
│   │   └── sources.list.template   # Generic template (<release> placeholder)
│   └── ubuntu-codenames.map        # Version → codename fallback map
├── scripts/
│   ├── iitd-proxy                  # Bash launcher (python3/python2 auto-detect)
│   └── iitd-proxy.py               # Proxy logic (Python 2.7 + 3.x compatible)
└── modules/
    ├── system/              # Install / uninstall tool
    │   └── module.sh
    ├── iitd_repo/           # IITD repository setup
    │   └── module.sh
    └── proxy/               # Installs iitd-proxy command (one-time)
        └── module.sh
```

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

## Proxy Module

Proxy module **sirf ek baar** `iitd-proxy` command system mein install karta hai. Uske baad proxy enable/disable baar-baar command se hota hai.

### Step 1: Install (ek baar, iitd-config se)

```bash
sudo ./iitd-config
# Menu se "Proxy Setup (Install iitd-proxy)" select karo
```

Yeh install karega:
- `/usr/local/bin/iitd-proxy` (launcher)
- `/usr/local/lib/iitd-tool/iitd-proxy.py`
- Dependencies: `python3` ya `python-minimal` (auto-detect) + `ca-certificates`

**Python 2 aur 3 dono supported** — sirf **system Python** use hota hai (`/usr/bin/python3` ya `/usr/bin/python2`). Pyenv, conda, `/usr/local` wale custom Python ignore hote hain.

### Step 2: Proxy enable (jitni baar chaho)

```bash
sudo iitd-proxy staff krajaymeena
sudo iitd-proxy phd ankit
sudo iitd-proxy btech USERID
```

Password prompt aayega (IITD kerberos/proxy password).

### Step 3: Proxy hatana (logout)

```bash
sudo iitd-proxy logout
```

Pure system se proxy remove ho jayegi.

### Kya configure hota hai

| Component | Method |
|-----------|--------|
| APT / apt store | `/etc/apt/apt.conf.d/95iitd-proxy` |
| Snap Store | `snap set system proxy.*` |
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
- Ubuntu 16.04 to 26.04
- Python 2.7 **or** Python 3.x from `/usr/bin` only (distro-managed; custom installs ignored)
- Root access (sudo) for system configuration modules
