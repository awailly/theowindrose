# Windrose Deep GPU Diagnostic & Trace Capture
# Run as Administrator via SSH before launching the game
# Usage:
#   .\windrose-trace.ps1 start    - Collect system info + start GPU trace
#   .\windrose-trace.ps1 stop     - Stop trace after hang occurs
#   .\windrose-trace.ps1 dump     - Capture memory dump of hung process

param([string]$Action = "start")

$dumpDir = "C:\CrashDumps"
New-Item -Path $dumpDir -ItemType Directory -Force | Out-Null

switch ($Action) {

"start" {
    Write-Host "=== WINDROSE GPU DIAGNOSTIC ===" -ForegroundColor Cyan
    $diag = "$dumpDir\diag.txt"
    "DIAGNOSTIC $(Get-Date)" | Out-File $diag

    # GPU info
    "`n--- GPU ---" | Out-File $diag -Append
    Get-WmiObject Win32_VideoController | Select-Object Name, DriverVersion, AdapterRAM, VideoProcessor | Format-List | Out-File $diag -Append

    # TDR
    "`n--- TDR SETTINGS ---" | Out-File $diag -Append
    $tdr = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -ErrorAction SilentlyContinue
    if ($tdr.TdrLevel -ne $null -or $tdr.TdrDelay -ne $null) {
        "TdrLevel: $($tdr.TdrLevel)  TdrDelay: $($tdr.TdrDelay)  TdrDdiDelay: $($tdr.TdrDdiDelay)" | Out-File $diag -Append
    } else {
        "DEFAULT (Level=3, Delay=2s)" | Out-File $diag -Append
    }

    # GPU events
    "`n--- GPU/DISPLAY EVENTS (last 30) ---" | Out-File $diag -Append
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display','nvlddmkm','dxgkrnl','dxgmms2'} -MaxEvents 30 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, ProviderName, Id, Message -Wrap | Out-File $diag -Append

    # TDR events specifically
    "`n--- TDR/DEVICE REMOVED EVENTS ---" | Out-File $diag -Append
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=14,4101,4097,10110,10111,10117} -MaxEvents 20 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, Message -Wrap | Out-File $diag -Append

    # Streamline DLLs
    "`n--- STREAMLINE DLLS ---" | Out-File $diag -Append
    Get-ChildItem -Recurse "C:\Program Files (x86)\Steam\steamapps\common\Windrose" -Filter "sl.*" -ErrorAction SilentlyContinue |
        Select-Object FullName, Length | Format-Table -AutoSize | Out-File $diag -Append

    # AMD remnants
    "`n--- AMD REMNANTS ---" | Out-File $diag -Append
    Get-Service "AMD*","ati*" -ErrorAction SilentlyContinue | Format-Table Name, Status, StartType | Out-File $diag -Append
    Get-ChildItem "C:\Windows\System32\ati*.dll" -ErrorAction SilentlyContinue | Select-Object Name | Out-File $diag -Append

    # Memory
    "`n--- MEMORY ---" | Out-File $diag -Append
    $os = Get-WmiObject Win32_OperatingSystem
    "Total: $([math]::Round($os.TotalVisibleMemorySize/1MB,1)) GB | Free: $([math]::Round($os.FreePhysicalMemory/1MB,1)) GB" | Out-File $diag -Append

    # Windows version
    "`n--- WINDOWS ---" | Out-File $diag -Append
    (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion") | Select-Object ProductName, DisplayVersion, CurrentBuildNumber, UBR | Format-List | Out-File $diag -Append

    # NVIDIA driver
    "`n--- NVIDIA DRIVER ---" | Out-File $diag -Append
    $nv = Get-ChildItem "C:\Windows\System32\nvwgf2umx.dll" -ErrorAction SilentlyContinue
    if ($nv) { "nvwgf2umx.dll version: $($nv.VersionInfo.FileVersion) date: $($nv.LastWriteTime)" | Out-File $diag -Append }

    Write-Host "Diagnostics saved to $diag" -ForegroundColor Green
    Write-Host ""

    # Start GPU trace
    Write-Host "Starting GPU kernel trace..." -ForegroundColor Yellow

    # Check if xperf is available
    $xperf = Get-Command xperf -ErrorAction SilentlyContinue
    if (-not $xperf) {
        $xperf = Get-Command "C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe" -ErrorAction SilentlyContinue
    }

    if ($xperf) {
        & $xperf.Source -on DiagEasy+PROC_THREAD+LOADER -f "$dumpDir\kernel.etl" 2>&1 | Out-Null
        & $xperf.Source -start dxgtrace -on "Microsoft-Windows-Dxgkrnl:0xFFFF:5" -f "$dumpDir\dxg.etl" 2>&1 | Out-Null
        Write-Host "GPU trace ACTIVE. Launch the game now." -ForegroundColor Green
        Write-Host "When it hangs, run: .\windrose-trace.ps1 dump" -ForegroundColor Cyan
        Write-Host "Then run: .\windrose-trace.ps1 stop" -ForegroundColor Cyan
    } else {
        Write-Host "xperf not found. Installing Windows Performance Toolkit..." -ForegroundColor Yellow
        # Try wpr (Windows Performance Recorder) as fallback - built into Windows
        $wpr = Get-Command wpr -ErrorAction SilentlyContinue
        if ($wpr) {
            wpr -start GPU -start GeneralProfile -filemode 2>&1 | Out-Null
            Write-Host "WPR GPU trace ACTIVE (using wpr instead of xperf)." -ForegroundColor Green
            Write-Host "When it hangs, run: .\windrose-trace.ps1 dump" -ForegroundColor Cyan
            Write-Host "Then run: .\windrose-trace.ps1 stop" -ForegroundColor Cyan
        } else {
            Write-Host "ERROR: Neither xperf nor wpr found." -ForegroundColor Red
            Write-Host "Install: winget install Microsoft.WindowsPerformanceToolkit" -ForegroundColor Yellow
            Write-Host "Or use Windows SDK installer and select 'Windows Performance Toolkit'" -ForegroundColor Yellow
        }
    }
}

"stop" {
    Write-Host "Stopping traces..." -ForegroundColor Yellow

    $xperf = Get-Command xperf -ErrorAction SilentlyContinue
    if (-not $xperf) { $xperf = Get-Command "C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe" -ErrorAction SilentlyContinue }

    if ($xperf) {
        & $xperf.Source -stop dxgtrace 2>&1 | Out-Null
        & $xperf.Source -stop 2>&1 | Out-Null
        & $xperf.Source -merge "$dumpDir\kernel.etl" "$dumpDir\dxg.etl" "$dumpDir\merged.etl" 2>&1 | Out-Null
        Write-Host "Trace saved to $dumpDir\merged.etl" -ForegroundColor Green
    } else {
        wpr -stop "$dumpDir\gpu_trace.etl" 2>&1 | Out-Null
        Write-Host "Trace saved to $dumpDir\gpu_trace.etl" -ForegroundColor Green
    }

    Write-Host "`nFiles in $dumpDir`:" -ForegroundColor Cyan
    Get-ChildItem $dumpDir | Format-Table Name, @{N='MB';E={[math]::Round($_.Length/1MB,1)}}, LastWriteTime
}

"dump" {
    Write-Host "Capturing dump of hung process..." -ForegroundColor Yellow
    $proc = Get-Process "Windrose-Win64-Shipping" -ErrorAction SilentlyContinue
    if (-not $proc) {
        Write-Host "Game process not found!" -ForegroundColor Red
        return
    }
    $dmpFile = "$dumpDir\windrose_$(Get-Date -Format 'yyyyMMdd_HHmmss').dmp"

    # Use Task Manager method via COM (most reliable)
    $proc | ForEach-Object {
        Write-Host "PID: $($_.Id) - Creating dump..." -ForegroundColor Yellow
        # Use procdump if available, otherwise comsvcs
        $pd = Get-Command procdump -ErrorAction SilentlyContinue
        if ($pd) {
            & procdump -ma -accepteula $_.Id $dmpFile 2>&1 | Out-Null
        } else {
            # comsvcs method - note the specific syntax required
            $cmd = "rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump $($_.Id) $dmpFile full"
            cmd /c $cmd 2>&1 | Out-Null
        }
    }

    if (Test-Path $dmpFile) {
        $sz = [math]::Round((Get-Item $dmpFile).Length/1MB, 1)
        Write-Host "Dump saved: $dmpFile ($sz MB)" -ForegroundColor Green
    } else {
        Write-Host "Dump failed. Trying alternative method..." -ForegroundColor Red
        # Fallback: use .NET MiniDumpWriteDump
        $code = @'
using System;
using System.Runtime.InteropServices;
using System.IO;
public class MiniDump {
    [DllImport("dbghelp.dll", SetLastError=true)]
    public static extern bool MiniDumpWriteDump(IntPtr hProcess, uint processId, IntPtr hFile, uint dumpType, IntPtr exceptionParam, IntPtr userStreamParam, IntPtr callbackParam);
}
'@
        Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
        $handle = [System.IO.File]::Create($dmpFile)
        $procHandle = (Get-Process -Id $proc.Id).Handle
        [MiniDump]::MiniDumpWriteDump($procHandle, $proc.Id, $handle.SafeFileHandle.DangerousGetHandle(), 2, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
        $handle.Close()
        if ((Get-Item $dmpFile -ErrorAction SilentlyContinue).Length -gt 0) {
            Write-Host "Dump saved (fallback method): $dmpFile" -ForegroundColor Green
        } else {
            Write-Host "All dump methods failed. Use Task Manager > Details > right-click > Create dump file" -ForegroundColor Red
        }
    }
}

"info" {
    # Quick display of diag file
    if (Test-Path "$dumpDir\diag.txt") { Get-Content "$dumpDir\diag.txt" }
    else { Write-Host "No diag.txt found. Run: .\windrose-trace.ps1 start" }
}

default {
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  .\windrose-trace.ps1 start  - Collect diagnostics + start GPU trace"
    Write-Host "  .\windrose-trace.ps1 dump   - Capture dump when game hangs"
    Write-Host "  .\windrose-trace.ps1 stop   - Stop trace + save ETL"
    Write-Host "  .\windrose-trace.ps1 info   - Display collected diagnostics"
}

}
