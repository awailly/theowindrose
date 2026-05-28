# Windrose Crash Investigation - Full Summary

## The Problem

Windrose (UE5 Early Access, Steam) freezes/hangs requiring force-kill. Happens reproducibly within 1-5 minutes of gameplay. Two failure modes observed:
1. **Software deadlock** — game hangs, no TDR event (fence wait without GPU submission)
2. **GPU TDR** — nvlddmkm fires Event 153, device removed, game dies

## System (confirmed via live diagnostics 2026-05-27)

- CPU: AMD Ryzen 7 7800X3D
- GPU: **NVIDIA GeForce RTX 3080 Ti**
- Driver: **32.0.15.9649 (v569.49)**
- iGPU: AMD Radeon Graphics (Driver 31.0.24002.92, 0.5GB VRAM) — **still registered as active adapter with drivers loaded**
- RAM: 32GB (20GB free at idle)
- OS: Windows 11 Pro 25H2 Build 26200.8457
- Game: Windrose v5.6.1.0, installed at `C:\Program Files (x86)\Steam\steamapps\common\Windrose`

## Root Cause Analysis

### Two distinct failure modes confirmed:

**Mode 1: Software deadlock (no TDR)**
- Observed at 17:51:12 on May 27 — game hung 52 seconds after launch
- No nvlddmkm event at that time
- Game recovered on its own (or appeared to)
- Cause: likely race condition in UE5 RHI layer or Streamline interposer

**Mode 2: GPU TDR (nvlddmkm Event 153)**
- Observed at 17:56 and 18:09 on May 27 — game crashed
- nvlddmkm 153 fires in clusters of 2-4 events within seconds
- **CRITICAL: Also fires when game is NOT running** (17:05 cluster, 6 events in 16s, game didn't launch until 17:50)
- This means the GPU itself is unstable independent of Windrose

### nvlddmkm Event 153 History

| Date/Time | Events | Game Running? |
|-----------|--------|---------------|
| May 23 17:34 | 3 | Unknown |
| May 23 18:34 | 5 | Yes (dump captured) |
| May 24 16:32 | 4 | Unknown |
| May 24 18:06 | 3 | Yes (dump captured) |
| May 24 19:06 | 3 | Unknown |
| May 24 19:47 | 3 | Unknown |
| May 24 19:57 | 3 | Unknown |
| **May 27 17:05** | **6** | **NO — game started at 17:50** |
| May 27 17:56 | 4 | Yes — game crashed |
| May 27 18:09 | 2 | Yes — game crashed |

### Key Insight

The GPU is TDR'ing even without the game. This points to:
1. Hardware instability (thermal, VRAM, power)
2. Driver conflict from dual-adapter (AMD iGPU still active)
3. Background process triggering GPU work that causes TDR

## AMD iGPU Status (still problematic)

Despite being "disabled", the AMD iGPU is still present:
- Shows as a display adapter in WMI
- AMD services still running: **AMD Crash Defender Service (Running, Automatic)**, AmdPpkgSvc (Running, Automatic)
- AMD DLLs still in System32: atieclxx.dll, atiadlxx.dll, atidxx64.dll, atig6txx.dll, etc.

## What We Tried (chronological)

| # | Action | Result |
|---|--------|--------|
| 1 | Disabled AMD iGPU via PowerShell | Still hangs — services/drivers still loaded |
| 2 | Disabled DLSS Frame Generation | Still hangs |
| 3 | Disabled NVIDIA Reflex | Still hangs, sl_interposer still loads |
| 4 | Disabled Steam Overlay in settings | DLL still injected |
| 5 | `-dx12` launch option | No effect (already DX12) |
| 6 | **Renamed all sl.*.dll** (Streamline removal) | **Still crashes — TDR at 18:09** |

## Streamline DLLs (now renamed to .disabled)

Located in two paths under game folder:
```
Windrose\R5\Builds\WindowsServer\R5\Plugins\3rdParty\DLSS\Plugins\StreamlineCore\Binaries\ThirdParty\Win64\
Windrose\R5\Plugins\3rdParty\DLSS\Plugins\StreamlineCore\Binaries\ThirdParty\Win64\
```
Files: sl.common.dll, sl.deepdvc.dll, sl.dlss_g.dll, sl.interposer.dll, sl.pcl.dll, sl.reflex.dll

## Other Processes Running During Crashes

- L-Connect-Service (Lian Li RGB) — 213MB, hooks GPU
- Discord — 574MB (keeping for communication)
- NVDisplay.Container — 171MB
- Multiple Brave tabs, WhatsApp, Steam

## Infrastructure

- **GitHub repo**: https://github.com/awailly/theowindrose (public)
- **Monitor**: `http://192.168.1.243:9999/` (endpoints: /status, /diag, /events, /log, /dump, /kill)
- **SSH**: Server installed, firewall opened, public key auth being set up
- **Auto-dump**: Watchdog captures dumps on hang (3 captured so far)

## Dumps Captured

| File | Size | When |
|------|------|------|
| Windrose-Win64-Shipping.DMP | 19.5GB | May 24 18:15 |
| windrose_HANG_20260527_175112.dmp | 9.2GB | May 27 17:51 (software deadlock) |
| windrose_HANG_20260527_180052.dmp | ? | May 27 18:00 |
| windrose_HANG_20260527_180538.dmp | ? | May 27 18:05 |

## Next Steps (updated priority)

1. **Get full nvlddmkm 153 event message** — need the actual text to see which GPU engine times out
2. **Properly disable AMD iGPU** — `Disable-PnpDevice` + stop/disable all AMD services + check if it disappears from adapter list
3. **Kill L-Connect-Service** (Lian Li RGB) — known to cause GPU issues
4. **GPU stress test outside game** (FurMark/3DMark) — confirm if GPU is stable without Windrose
5. **GPU kernel trace (ETL)** during hang — see what dxgkrnl reports
6. **Try `-dx11`** — bypasses D3D12 entirely
7. **DDU clean install** — if GPU is only unstable with current driver
8. **Check GPU thermals** — if TDR happens under any GPU load, it's hardware
