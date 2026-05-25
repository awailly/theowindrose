# Windrose Crash Investigation - Full Summary

## The Problem

Windrose (UE5 Early Access, Steam) freezes/hangs requiring force-kill. Not a crash with a dialog — a complete hang. Happens reproducibly within ~20 minutes of gameplay.

## System

- CPU: AMD Ryzen 7 7800X3D
- GPU: NVIDIA (exact model TBD — diagnostics not yet collected)
- iGPU: AMD Radeon (now disabled via PowerShell)
- RAM: Unknown total (was under pressure from 17 Brave processes + Epic + Steam)
- OS: Windows 11 (Build 26100)
- Game: Windrose v5.6.1.0, installed at `C:\Program Files (x86)\Steam\steamapps\common\Windrose`
- Game has no `Saved` folder — never writes logs

## Root Cause (confirmed via 2 WinDbg dumps)

**D3D12 GPU fence deadlock.** The GPU stops responding to submitted command lists.

Chain of events:
1. UE5 RHIThread submits D3D12 command list via `ID3D12CommandQueue`
2. RHIThread calls `WaitOnAddress` waiting for GPU fence signal
3. GPU never signals the fence
4. RenderThread blocks waiting on RHI
5. RHISubmissionThread blocks waiting on RenderThread
6. GameThread blocks in `GetMessageW` (message pump starved — can't submit new frames)

Both dumps have identical `FAILURE_ID_HASH: {3112b5eb-303b-e877-0655-90bdfa336126}`.

## DLLs Loaded in Process (problematic ones)

| DLL | Who Loads It | Why It Matters |
|-----|-------------|----------------|
| `sl_interposer.dll` | Game binary (Streamline SDK bundled) | Hooks D3D12 Present path. Loaded even with DLSS Frame Gen OFF and Reflex OFF. Has its own "sl.log" thread. |
| `gameoverlayrenderer64.dll` | Steam (injected via CreateRemoteThread) | Hooks `GetMessageW` via `OverlayHookD3D3`. Loaded even with Steam Overlay disabled in settings. |
| `NvTelemetryAPI64.dll` | NVIDIA driver (nvwgf2umx.dll) | In-process telemetry. Sleeping on condition variable — probably not causal but adds noise. |
| `nvcuda64.dll` | NVIDIA driver | Multiple threads in wait states. |

## What We Tried (all failed to fix)

1. ✅ Disabled AMD iGPU (killed atieclxx/atiesrxx, disabled via PowerShell) → still hangs
2. ✅ Disabled DLSS Frame Generation in game settings → still hangs
3. ✅ Disabled NVIDIA Reflex in game settings → still hangs, `sl_interposer.dll` still loads
4. ✅ Disabled Steam Overlay in Steam settings → `gameoverlayrenderer64.dll` still injected and hooking
5. ✅ Added `-dx12` launch option → game was already DX12, no change

## What We Have NOT Yet Tried

1. **Remove Streamline DLLs** from game folder (rename all `sl.*.dll` files) — forces game to run without Streamline hooks
2. **Rename `gameoverlayrenderer64.dll`** in Steam folder — prevents injection entirely
3. **Check TDR settings** — if TdrLevel=0, Windows won't reset the GPU, causing infinite hang instead of crash+recovery
4. **DDU clean NVIDIA driver reinstall** — clears stale multi-adapter state from when AMD iGPU was active
5. **`-dx11` launch option** — bypasses D3D12 fence mechanism entirely
6. **GPU kernel trace (ETL)** — captures what the GPU scheduler sees when the fence stops signaling
7. **Custom D3D12 fence monitor DLL** — hooks `ID3D12CommandQueue::Signal` to log fence submissions and detect stale fences

## Key Diagnostic Questions Still Unanswered

1. What is the exact GPU model and driver version?
2. Is TDR disabled in registry? (Would explain infinite hang vs crash)
3. Are there any `nvlddmkm` or `dxgkrnl` events in Event Viewer around hang time?
4. What Streamline DLLs exist in the game folder? (Need exact paths to rename)
5. Are AMD driver remnants still installed as services?

## Tools & Repo Created

**GitHub repo**: https://github.com/awailly/theowindrose (public)

Contains:
- `scripts/windrose-monitor.ps1` — HTTP server (port 9999) that auto-detects hangs, captures dumps, exposes diagnostics via curl endpoints (`/status`, `/diag`, `/events`, `/log`, `/dump`, `/kill`)
- `scripts/kill-display-hijackers.ps1` — kills MSI Center, AMD remnants, NVIDIA overlay/telemetry, Discord, RGB software, Epic launcher
- `scripts/windrose-trace.ps1` — captures GPU kernel ETL traces via xperf/wpr
- `docs/investigation.md` — technical investigation notes
- `README.md` — kid-friendly step-by-step instructions (download zip, no git needed)

## Remote Access Setup

- SSH server setup instructions in README (not yet confirmed running)
- Monitor script exposes HTTP on port 9999 for curl-based remote diagnostics
- Kid just needs to: download zip → extract → run PowerShell as admin → run monitor → tell dad the IP

## Recommended Next Steps (in priority order)

1. **Get diagnostics first** — `curl http://<ip>:9999/diag` once monitor is running. This tells us GPU model, driver version, TDR settings, and Streamline DLL paths.
2. **Rename Streamline DLLs** — `Get-ChildItem -Recurse "C:\Program Files (x86)\Steam\steamapps\common\Windrose" -Filter "sl.*" | Rename-Item -NewName { $_.Name + ".disabled" }` — test if game runs without them.
3. **Rename Steam overlay DLL** — `Rename-Item "C:\Program Files (x86)\Steam\gameoverlayrenderer64.dll" "gameoverlayrenderer64.dll.disabled"` — test without the GetMessage hook.
4. **Check/fix TDR** — if TdrLevel is 0 or TdrDelay is very high, reset to defaults so Windows properly resets the GPU instead of hanging forever.
5. **GPU kernel trace** — if still hanging after removing hooks, capture ETL to see what the GPU scheduler reports.
6. **DDU + fresh driver** — if trace shows driver-level issue.
7. **`-dx11`** — nuclear option, bypasses D3D12 entirely.
8. **Report to game devs** — if it's a game bug (D3D12 fence race condition in their RHI layer).
