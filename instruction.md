# IITD Lab Setup Tool — Instructions

> Project change hone par yahi file update karo.  
> Repo: https://github.com/karpus2807/iitd_tools

Ubuntu **16.04 – 26.04** lab systems ke liye — IITD repo + proxy setup.

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

### `2` — IITD Repository Setup (submenu)

| # | Option |
|---|--------|
| 1 | Backup sources.list |
| 2 | Apply IITD mirror |
| 3 | Disable ubuntu.sources |
| 4 | Disable 3rd party repos |
| 5 | Run apt update |
| 6 | Restore original status |
| b | Back |

### `3` — Proxy Setup (Install iitd-proxy)

`iitd-proxy` ek baar install → phir commands se use karo  
Install ke saath **IITD CA certificate** (`CCIITD-CA.crt`) system trust store mein add hota hai — campus HTTPS / proxy login ke liye.

### `4` — Basic Tools Installer

Checkbox list se tools chun kar install karo:

- ↑/↓ move · **SPACE** toggle · **ENTER** install · **q** cancel  
- (whiptail available ho to woh UI use hota hai)

**Tools list:** wget, curl, tmux, ssh, ssh server, ifconfig (net-tools), git, vim, htop, rsync, build-essential, ...  
→ `config/basic-tools.list`

### `q` — Quit

---

## Proxy commands (menu 3 ke baad)

```bash
sudo iitd-proxy <role> <userid>    # proxy ON
sudo iitd-proxy logout             # proxy OFF
sudo iitd-proxy shell              # interactive (exit to quit)
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
| 2026-07-09 | IITD CA certificate (CCIITD-CA.crt) integrated in proxy TLS |
| 2026-07-09 | Repo submenu, restore, system data dir |
| 2026-07-09 | Direct install before proxy failsafe |

---

*Har change ke baad change log update karo.*
