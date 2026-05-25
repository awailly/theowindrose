# Kill processes that may interfere with GPU/display
# Run as Administrator before launching the game

$targets = @(
    # MSI Center / Dragon Center
    "CC_Engine_x64", "MSI Center", "MSIService", "mystic_light_service",
    # AMD iGPU remnants
    "atieclxx", "atiesrxx", "AMDRSServ", "RadeonSoftware",
    # NVIDIA overlay/telemetry (not the driver itself)
    "NVDisplay.Container", "NVIDIA Share", "NVIDIA Web Helper",
    "nvcontainer", "NvTelemetryContainer",
    # Discord (hung previously)
    "Discord", "DCv2",
    # RGB / hardware monitoring
    "LightingService", "RGBFusion", "iCUE", "SignalRgb",
    "NZXT CAM", "HWiNFO64", "HWiNFO32", "MSIAfterburner",
    "RTSS",  # RivaTuner Statistics Server
    # Game launchers (not Steam)
    "EpicGamesLauncher", "EpicWebHelper",
    # Wallpaper engines
    "Wallpaper32", "wallpaper64"
)

$killed = @()
$notFound = @()

foreach ($name in $targets) {
    $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        $killed += $name
    } else {
        $notFound += $name
    }
}

Write-Host "`n=== KILLED ===" -ForegroundColor Green
if ($killed) { $killed | ForEach-Object { Write-Host "  $_" } }
else { Write-Host "  (none found)" }

Write-Host "`n=== NOT RUNNING ===" -ForegroundColor DarkGray
$notFound | ForEach-Object { Write-Host "  $_" }

Write-Host "`nDone. Launch the game now." -ForegroundColor Cyan
