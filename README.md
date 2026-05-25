# 🧭 Windrose Crash Detective Kit

Hey Theo! This repo has the tools to figure out why Windrose keeps freezing on your PC.

## What's Happening

Windrose freezes because the GPU (your graphics card) stops answering when the game asks it to draw things. We're going to catch it in the act.

## 🚀 Quick Start (Do These Steps In Order)

### Step 1: Open PowerShell as Admin

1. Right-click the **Start button** (Windows icon, bottom left)
2. Click **"Terminal (Admin)"** or **"Windows PowerShell (Admin)"**
3. Click **Yes** when it asks permission

### Step 2: Allow Scripts to Run

Paste this and press Enter:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
```

### Step 3: Go to the Scripts Folder

```powershell
cd C:\CrashDumps
```

(If the folder doesn't exist yet, paste: `New-Item -Path C:\CrashDumps -ItemType Directory -Force`)

### Step 4: Kill Background Junk

This stops programs that might interfere with the GPU:
```powershell
.\kill-display-hijackers.ps1
```

### Step 5: Start the Monitor

```powershell
.\windrose-monitor.ps1
```

It will print something like:
```
HTTP server listening on port 9999
Local IP(s):
  192.168.1.XX
Waiting for requests...
```

**Tell Dad the IP address it shows.** Then launch Windrose and play normally.

### Step 6: Play the Game

Just play! When it freezes:
- **Don't touch anything for 30 seconds** — the monitor auto-captures a dump
- Then you can kill the game (the monitor does `/kill` or use Task Manager)

---

## 📁 What's in This Repo

| File | What It Does |
|------|-------------|
| `scripts/windrose-monitor.ps1` | Watches the game, auto-captures crash data, lets Dad check remotely |
| `scripts/kill-display-hijackers.ps1` | Kills MSI Center, RGB software, and other GPU-hogging junk |
| `scripts/windrose-trace.ps1` | Captures deep GPU traces (Dad will tell you when to use this) |
| `docs/investigation.md` | Notes on what we've found so far |

## 🖥️ For Dad (Remote Access)

Once the monitor is running on Theo's PC:

```bash
# Check if game is running and if it's hung
curl http://<theos-ip>:9999/status

# Get full system diagnostics
curl http://<theos-ip>:9999/diag

# GPU event log (TDR events, errors)
curl http://<theos-ip>:9999/events

# See hang detection log
curl http://<theos-ip>:9999/log

# Trigger a manual dump
curl http://<theos-ip>:9999/dump

# Kill the game remotely
curl http://<theos-ip>:9999/kill
```

## 🔧 Setup (First Time Only)

### Enable SSH (so Dad can run commands remotely)

In the Admin PowerShell:
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
```

Then Dad can SSH in:
```bash
ssh theo@<theos-ip>
```

### Copy Scripts to C:\CrashDumps

Copy all files from the `scripts/` folder to `C:\CrashDumps\` on your PC.

---

## 🕵️ Investigation Status

- [x] Confirmed: GPU fence deadlock (GPU stops responding to D3D12 commands)
- [x] Confirmed: `sl_interposer.dll` (NVIDIA Streamline) loads even with Reflex off
- [x] Confirmed: `gameoverlayrenderer64.dll` hooks GetMessage even with overlay disabled
- [x] Disabled AMD iGPU
- [x] Disabled Reflex
- [ ] **NEXT**: Get diagnostics (TDR settings, driver version, Streamline DLL paths)
- [ ] Remove Streamline DLLs from game folder
- [ ] Remove Steam overlay hook
- [ ] GPU kernel trace during hang
