# IITD Lab Setup Tool — Instructions & Change Log

> **Living document:** project mein jo bhi change ho, yahan update karte raho.  
> Repo: https://github.com/karpus2807/iitd_tools

---

## Project Overview

IITD lab ke naye Ubuntu systems (16.04–26.04) configure karne ke liye menu-driven tool.

| Item | Value |
|------|-------|
| Entry command | `sudo ./iitd-config` |
| Proxy command | `sudo iitd-proxy <role> <userid>` |
| Proxy logout | `sudo iitd-proxy logout` |
| Proxy shell | `sudo iitd-proxy shell` (type `exit` to quit) |

---

## Current Modules

| Module | Status | Description |
|--------|--------|-------------|
| `iitd_repo` | ✅ Ready | IITD apt mirror (`repo.iitd.ernet.in`), `ubuntu.sources` disable |
| `proxy` | ✅ Ready | One-time `iitd-proxy` install; repeated enable/logout via command |

---

## Architecture Notes

- **Modular:** `modules/*/module.sh` auto-discover hote hain menu mein
- **Repo:** ek template `config/repos/sources.list.template` — `<release>` codename se replace
- **Python:** sirf system `/usr/bin/python3` ya `python2` (custom Python ignore)
- **Startup:** OS + Python + dependency warmup; missing deps → **Failsafe Mode** (proxy shell → install → reboot)

---

## Required Dependencies

Fixed list: `config/dependencies.list`

- APT: `ca-certificates`, `python3` / `python-minimal` (auto)
- Python stdlib: argparse, ssl, urllib, json, … (iitd-proxy ke liye)

---

## IITD Proxy Roles

| Role | Prefix |
|------|--------|
| btech | 22 |
| mtech | 62 |
| phd | 61 |
| staff | 78 |
| faculty | 82 |
| visitor | 21 |

---

## Install Paths (after proxy module)

| Path | Purpose |
|------|---------|
| `/usr/local/bin/iitd-proxy` | Launcher |
| `/usr/local/lib/iitd-tool/iitd-proxy.py` | Proxy logic |
| `/usr/local/lib/iitd-tool/python.sh` | System Python detection |
| `/etc/apt/iitd-tool-backup/` | Repo config backups |
| `/var/log/iitd-proxy.log` | Proxy log |

---

## Change Log

### 2026-07-09 — Initial release

- Project structure: `iitd-config`, `lib/`, `config/`, `modules/`, `scripts/`
- Ubuntu 16.04–26.04 detection + codename map
- **IITD Repo module:** template-based `sources.list`, `ubuntu.sources` disable
- **Proxy module:** `iitd-proxy` install + system-wide proxy (apt, snap, GUI, wget, curl, browsers)
- Python 2.7 + 3.x support; system Python only
- Startup dependency warmup + Failsafe Mode (proxy shell → auto-install → normal reboot)
- `iitd-proxy shell` with `exit` command
- Cleanup: removed old reference script and cache files
- GitHub repo: `karpus2807/iitd_tools`

---

## How to Update This File

Har meaningful change ke baad **Change Log** mein naya entry add karo:

```markdown
### YYYY-MM-DD — Short title

- Kya change hua
- Kaunsi file/module affect hui
- User-facing command change (agar ho)
```

Agar architecture / module list badle to upar wale sections bhi update karo.

---

## Planned / Future (update as done)

- [ ] Additional lab modules (add here when started)
- [ ] ...

---

## Quick Commands (lab use)

```bash
# Tool chalao
cd /path/to/iitd_tool
chmod +x iitd-config
sudo ./iitd-config

# Proxy (install ke baad)
sudo iitd-proxy staff YOUR_USERID
sudo iitd-proxy logout

# Manual proxy shell
sudo iitd-proxy shell
```
