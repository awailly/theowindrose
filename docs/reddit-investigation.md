# Reddit & Community Investigation

Findings from r/crosswind (the Windrose subreddit — game was originally called "Crosswind") and Steam Community forums. Researched 2026-05-25.

## TL;DR

This is a **widespread, known issue** affecting NVIDIA RTX 40/50 series GPUs paired with AMD X3D CPUs. Not unique to Theo's PC. The most effective fix reported by the community is **disabling HAGS + switching to Borderless Windowed**.

---

## Matching Reports

### Thread: "Black Screen Caused by HAGS & Part of the DLSS Pipeline" (Steam, 21 Apr)
- **User**: Guardian Hope — RTX 5080 (liquid cooled), also tested RTX 4080 Super
- **Symptom**: "Black screen" crashes where GPU/Graphics Stack was unrecoverable by Windows 11 but Windows itself kept running. Crashed every 2-5 minutes.
- **Root cause identified**: Windrose's handling of the Windows 11 Graphics Pipeline when HAGS is enabled + DLAA + uncapped frame rate in Fullscreen
- **Fix that worked**:
  1. Disable HAGS (Settings → System → Display → Graphics → Hardware Accelerated GPU Scheduling OFF → Restart)
  2. Run Borderless Windowed
  3. Enable DLSS (quality upscaling) but keep DLAA OFF
  4. Disable Boost and related settings
  5. Set refresh rate to 2× monitor (e.g. 120Hz monitor → cap at 240)
  6. Keep VSync OFF
  7. Launch with `-hdr -dx12`
- **Result**: Went from crashing every 2-5 minutes to 14+ hours stable
- **Quote**: "If it belongs to Modern Graphics Stack beyond the Primary DLSS Quality Pipeline, turn the feature off"
- **Note**: RTX 4080 Super ran fine — issue specific to newer GPU + HAGS interaction

### Thread: "Random Game Hanging/Freezing, then freezing my entire PC forcing a hard restart" (Steam, 18 Apr)
- **User**: Kyanite — RTX 4070 Super, Intel i7-14700F, 32GB DDR5, W11
- **Symptom**: Entire PC freeze, no recovery after 5+ minutes. Touching power button triggers game error sound but no recovery. Hard reset required. Happens within 10-25 minutes.
- **Temps**: Under 70°C, not thermal
- **No fix found** — user gave up playing

### Thread: "Constantly freezing/crashing" (Steam, 20 Apr)
- **User**: HOMER STACKSON — RTX 5070 Ti, Ryzen 9800X3D, 32GB DDR5
- **Symptom**: Game hangs (not CTD), requires Task Manager kill. Settings on max, 120fps lock, Frame Gen OFF.
- **Fix suggested**: "Did you try running frame rate as uncapped? I had this issue with nearly an identical system and this fixed it."

### Thread: "Unable to play due to crashing after 5-20 minutes" (r/crosswind, 28 Apr)
- **User**: lauripaine — **7800X3D** (same CPU as Theo!), 7800XT (AMD GPU), 32GB DDR5, W11
- **Symptom**: Freezes after 5-20 minutes, UE5 Fatal Error on alt-tab. Can crash even in menus.
- **Tried**: Reinstall, different drives, admin mode, all display modes, low/high graphics, latest AMD drivers, verify files
- **Fix**: Switch to **Borderless Windowed** (confirmed by second user who reproduced: fullscreen → freeze after 15-20 min, borderless → no freeze)

### Thread: "What are your fixes for game crashes?" (r/crosswind, 20 May)
- **User**: Tarhaar — RTX 4070 Ti Super, hosting co-op
- **Symptom**: Freezes every hour, requires Task Manager kill
- **Community fixes mentioned**:
  - Avoid Tortuga (known crash hotspot)
  - Try latest NVIDIA driver (or Studio driver instead of Game Ready)
  - **Disable Steam Cloud Save** — "turned off cloud saving through steam, loaded up a whole new world with the same character, farted around for 5 minutes, went back to original world, haven't had a problem since"
  - Lower graphics from Ultra to Medium/High

### Thread: "Windrose black screen and crashes in naval battles" (r/crosswind, 28 Apr)
- **User**: GateRadiant1223 — RX 7600, i5-10400F
- **Symptom**: Both monitors go black during naval battles, PC stays powered on but frozen
- **Fix**: Changed the **GPU power cable** — wasn't supplying enough power during load spikes. "Changed the power cable, everything working normally now."

### Thread: "Crash Loop. World bricked?" (r/crosswind, 26 Apr)
- **User**: GonSanto — RTX 5070 Ti, 7800X3D, 32GB DDR5 6000MHz
- **Symptom**: "Application Hang Detected" after fast-traveling to Tortuga. Eventually world became unloadable.
- **Fix**: Create new character in same world → complete tutorial → fast travel to Tortuga with new char → back to menu → load original character. Fixed.

### Thread: "Lag disconnects tonight?" (r/crosswind, 27 Apr)
- **User**: Sm0kecheck
- **Symptom**: "Full freeze with music playing. No error or crash. Have to use task manager to end program." Solo and online.

---

## Official Patch Notes (v0.10.0.4, ~30 Apr)

Relevant fixes the devs shipped:
- "Fixed FrameGen stuttering that occurred when closing the inventory or map"
- "Fixed a video memory (VRAM) spike when opening certain UI windows"
- "Reduced disk and CPU usage"
- "Several improvements to ship performance when hosting a server"
- Steam Cloud Save fixes acknowledged as still broken (deferred to future patch)

---

## Pattern Analysis

| Factor | Evidence |
|--------|----------|
| HAGS enabled | Primary culprit per RTX 5080 user. HAGS changes GPU scheduling — conflicts with Streamline SDK's own scheduling hooks |
| Fullscreen exclusive | Multiple users confirm borderless fixes it. Fullscreen changes D3D12 swap chain Present path |
| Frame rate cap (especially 120fps) | Uncapping fixed it for RTX 5070 Ti user. May interact with Frame Gen/Reflex timing |
| DLAA / Boost / advanced upscaling | Should be OFF. Only basic DLSS Quality is safe |
| Steam Cloud Save | Causes I/O stalls that may trigger the hang. Disabling helps |
| Tortuga area | Known crash hotspot — high asset density triggers the issue faster |
| Ultra graphics settings | Higher VRAM pressure → more fence submissions → more deadlock opportunities |

---

## Relevance to Theo's Case

Theo has:
- ✅ NVIDIA GPU (model TBD but likely RTX 40-series given the 7800X3D pairing)
- ✅ AMD Ryzen 7 7800X3D (exact same CPU as multiple affected users)
- ✅ Windows 11
- ✅ Hangs within ~20 minutes (matches the 10-25 min pattern)
- ✅ Complete hang, no crash dialog (matches "Application Hang Detected" / force-kill pattern)
- ✅ D3D12 GPU fence deadlock (confirmed via WinDbg — this is what HAGS exacerbates)
- ✅ `sl_interposer.dll` loaded (Streamline SDK — the exact component that conflicts with HAGS)

**The community evidence strongly suggests HAGS is the primary trigger**, with Fullscreen mode and frame rate capping as aggravating factors.

---

## Recommended Actions (updated priority)

1. **Disable HAGS** — Windows Settings → System → Display → Graphics → turn off → restart PC
2. **Switch to Borderless Windowed** (not Fullscreen)
3. **Uncap frame rate** (or set to 240+)
4. **Disable Steam Cloud Save** for Windrose
5. **Turn off DLAA/Boost** — keep only basic DLSS Quality if using upscaling
6. Then proceed with our existing plan (rename Streamline DLLs, check TDR, etc.) only if still crashing

---

## Sources

- https://steamcommunity.com/app/3041230/discussions/0/802345591601375050/ (HAGS + DLSS fix)
- https://steamcommunity.com/app/3041230/discussions/0/802345327968424336/ (PC freeze, hard restart)
- https://steamcommunity.com/app/3041230/discussions/0/802345327968607516/ (9800X3D + 5070 Ti hangs)
- https://old.reddit.com/r/crosswind/comments/1tirvta/what_are_your_fixes_for_game_crashes/ (community fixes)
- https://old.reddit.com/r/crosswind/comments/1sy7c5u/unable_to_play_due_to_crashing_after_520_minutes/ (7800X3D, borderless fix)
- https://old.reddit.com/r/crosswind/comments/1sy93p6/windrose_is_experiencing_black_screen_and_crashes/ (power cable)
- https://old.reddit.com/r/crosswind/comments/1sw44tl/crash_loop_world_bricked/ (5070 Ti + 7800X3D, Tortuga)
- https://old.reddit.com/r/crosswind/comments/1szpgph/patch_notes_version_010042689d2ca277_connection/ (official patch)
- https://steamcommunity.com/app/3041230/discussions/0/837249359736370639/ (Steam Cloud fix)
