# Windrose GPU Hang Investigation

## Summary

Windrose (UE5, Early Access) hangs requiring force-kill. Not a crash — a deadlock.

## System

- CPU: AMD Ryzen 7 7800X3D
- GPU: NVIDIA (model TBD)
- iGPU: AMD Radeon (disabled)
- OS: Windows 11
- Game: Windrose v5.6.1.0 (Steam)

## Root Cause (confirmed via WinDbg)

D3D12 GPU fence deadlock:
1. Game submits D3D12 command list to GPU
2. GPU never signals fence completion
3. RHIThread blocks on `WaitOnAddress` forever
4. RenderThread blocks waiting on RHI
5. GameThread blocks in message pump (can't submit new frames)

## DLLs Involved

| DLL | Loaded By | Purpose | Problem |
|-----|-----------|---------|---------|
| `sl_interposer.dll` | Game (Streamline SDK) | DLSS/Reflex/Frame Gen | Hooks Present path, loaded even with features OFF |
| `gameoverlayrenderer64.dll` | Steam (injected) | Steam Overlay | Hooks GetMessage, loaded even with overlay OFF |
| `NvTelemetryAPI64.dll` | NVIDIA driver | Telemetry | Loaded by nvwgf2umx.dll |
| `nvcuda64.dll` | NVIDIA driver | CUDA | Multiple threads waiting |

## What We've Tried

- [x] Disabled AMD iGPU → still hangs
- [x] Disabled DLSS Frame Generation → still hangs
- [x] Disabled NVIDIA Reflex → still hangs (sl_interposer still loads)
- [x] Disabled Steam Overlay in settings → DLL still injected
- [x] Killed background processes (MSI Center, Discord, Epic) → still hangs

## Next Steps

1. Get TDR registry settings (is TDR disabled? that would explain infinite hang vs crash)
2. Get exact GPU model + driver version
3. Rename/remove `sl_interposer.dll` and all `sl.*.dll` from game folder
4. Rename `gameoverlayrenderer64.dll` in Steam folder
5. Capture GPU kernel trace (ETL) during hang
6. If still hangs: DDU clean driver install
7. If still hangs: try `-dx11` launch option
8. If still hangs: game bug, report to devs with dump

## Dump Analysis

Two dumps captured, both show identical pattern:
- `FAILURE_ID_HASH: {3112b5eb-303b-e877-0655-90bdfa336126}`
- `FAILURE_BUCKET: BREAKPOINT_80000003_win32u.dll!NtUserGetMessage`
- All render threads in wait state
- GPU fence never signals

## Key Threads in Dump

| Thread | Name | State | Meaning |
|--------|------|-------|---------|
| 0 | GameThread | `NtUserGetMessage` | Blocked in message pump |
| 39 | RHISubmissionThread | `WaitForSingleObject` | Waiting for render work |
| 40 | RHIThread | `WaitOnAddress` | Waiting for GPU fence |
| 41 | RenderThread | `WaitForSingleObject` | Waiting on RHI fence |
| 38 | RHIInterruptThread | `WaitForSingleObject` | Waiting for GPU interrupt |
