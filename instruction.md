# IITD Lab Setup Tool — Instructions

> Project change hone par yahi file update karo.  
> Repo: https://github.com/karpus2807/iitd_tools

Ubuntu **16.04 – 26.04** lab systems ke liye — IITD repo + proxy setup.

---

## Setup (pehli baar)

```bash
git clone https://github.com/karpus2807/iitd_tools.git
cd iitd_tools
chmod +x iitd-config
sudo ./iitd-config
```

---

## Tool commands

```bash
sudo ./iitd-config          # main menu
```

**Menu modules:**
1. **IITD Repository Setup** — `repo.iitd.ernet.in` mirror lagata hai  
2. **Proxy Setup** — `iitd-proxy` command install karta hai (ek baar)

---

## Proxy commands

Pehle menu se proxy module se install karo, phir:

```bash
sudo iitd-proxy <role> <userid>    # proxy ON
sudo iitd-proxy logout             # proxy OFF
sudo iitd-proxy shell              # interactive login (type exit to quit)
```

**Examples** (userid apna IITD ID likho):

```bash
sudo iitd-proxy staff krajaymeena
sudo iitd-proxy phd ankit
sudo iitd-proxy btech ee1234567
sudo iitd-proxy logout
```

**Roles:** `btech` · `mtech` · `phd` · `staff` · `faculty` · `visitor`

Password prompt aayega — IITD proxy password do.

---

## Agar dependencies missing hon

**Step 1:** Bina proxy — internet + IITD repo check → direct install try  
**Step 2:** Agar fail ho → Failsafe (proxy shell) → login → install

Cancel: prompt par **`exit`**

---

## Change log

| Date | Update |
|------|--------|
| 2026-07-09 | Direct install before proxy failsafe (internet + IITD repo check) |

---

*Har change ke baad upar change log mein ek line add karo.*
