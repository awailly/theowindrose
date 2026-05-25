# Windrose Auto-Monitor
# Runs continuously, watches for game hang, auto-captures dump + diagnostics
# Exposes results via a simple HTTP server so you can curl from your Mac
#
# Run as Administrator: .\windrose-monitor.ps1
# From your Mac: curl http://<kids-ip>:9999/status
#                curl http://<kids-ip>:9999/diag
#                curl http://<kids-ip>:9999/log
#                curl http://<kids-ip>:9999/events

$port = 9999
$dumpDir = "C:\CrashDumps"
$logFile = "$dumpDir\monitor.log"
New-Item -Path $dumpDir -ItemType Directory -Force | Out-Null

function Log($msg) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    Write-Host $line
    $line | Out-File $logFile -Append
}

# Collect initial diagnostics
function Get-Diag {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("=== DIAGNOSTICS $(Get-Date) ===")

    [void]$sb.AppendLine("`n--- GPU ---")
    Get-WmiObject Win32_VideoController | ForEach-Object { [void]$sb.AppendLine("$($_.Name) | Driver: $($_.DriverVersion) | VRAM: $([math]::Round($_.AdapterRAM/1GB,1))GB") }

    [void]$sb.AppendLine("`n--- TDR ---")
    $tdr = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -ErrorAction SilentlyContinue
    if ($tdr.TdrLevel -ne $null) { [void]$sb.AppendLine("TdrLevel=$($tdr.TdrLevel) TdrDelay=$($tdr.TdrDelay)") }
    else { [void]$sb.AppendLine("DEFAULT (Level=3, Delay=2s)") }

    [void]$sb.AppendLine("`n--- NVIDIA DRIVER ---")
    $nv = Get-ChildItem "C:\Windows\System32\nvwgf2umx.dll" -ErrorAction SilentlyContinue
    if ($nv) { [void]$sb.AppendLine("$($nv.VersionInfo.FileVersion) ($($nv.LastWriteTime))") }

    [void]$sb.AppendLine("`n--- STREAMLINE DLLS ---")
    Get-ChildItem -Recurse "C:\Program Files (x86)\Steam\steamapps\common\Windrose" -Filter "sl.*" -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$sb.AppendLine("$($_.FullName) ($($_.Length) bytes)") }

    [void]$sb.AppendLine("`n--- AMD REMNANTS ---")
    Get-Service "AMD*","ati*" -ErrorAction SilentlyContinue | ForEach-Object { [void]$sb.AppendLine("$($_.Name): $($_.Status) ($($_.StartType))") }
    Get-ChildItem "C:\Windows\System32\ati*.dll" -ErrorAction SilentlyContinue | ForEach-Object { [void]$sb.AppendLine($_.Name) }

    [void]$sb.AppendLine("`n--- MEMORY ---")
    $os = Get-WmiObject Win32_OperatingSystem
    [void]$sb.AppendLine("Total: $([math]::Round($os.TotalVisibleMemorySize/1MB,1))GB | Free: $([math]::Round($os.FreePhysicalMemory/1MB,1))GB")

    [void]$sb.AppendLine("`n--- WINDOWS ---")
    $w = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    [void]$sb.AppendLine("$($w.ProductName) $($w.DisplayVersion) Build $($w.CurrentBuildNumber).$($w.UBR)")

    $sb.ToString()
}

function Get-GpuEvents {
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("=== GPU/DISPLAY EVENTS ===")
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display','nvlddmkm','dxgkrnl','dxgmms2'} -MaxEvents 30 -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$sb.AppendLine("[$($_.TimeCreated)] [$($_.ProviderName)] ID=$($_.Id) $($_.Message)") }
    [void]$sb.AppendLine("`n=== TDR EVENTS ===")
    Get-WinEvent -FilterHashtable @{LogName='System'; Id=14,4101,4097,10110,10111,10117} -MaxEvents 10 -ErrorAction SilentlyContinue |
        ForEach-Object { [void]$sb.AppendLine("[$($_.TimeCreated)] ID=$($_.Id) $($_.Message)") }
    $sb.ToString()
}

function Get-Status {
    $proc = Get-Process "Windrose-Win64-Shipping" -ErrorAction SilentlyContinue
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("=== STATUS $(Get-Date) ===")
    if ($proc) {
        [void]$sb.AppendLine("GAME RUNNING | PID: $($proc.Id) | CPU: $($proc.CPU)s | RAM: $([math]::Round($proc.WorkingSet64/1MB))MB")
        [void]$sb.AppendLine("Responding: $($proc.Responding)")
        [void]$sb.AppendLine("Threads: $($proc.Threads.Count)")
        [void]$sb.AppendLine("Start: $($proc.StartTime)")
        [void]$sb.AppendLine("Uptime: $([math]::Round(((Get-Date) - $proc.StartTime).TotalMinutes, 1)) min")
    } else {
        [void]$sb.AppendLine("GAME NOT RUNNING")
    }
    [void]$sb.AppendLine("`n--- Top Processes ---")
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 | ForEach-Object {
        [void]$sb.AppendLine("  $($_.Name) | $([math]::Round($_.WorkingSet64/1MB))MB | Responding: $($_.Responding)")
    }
    [void]$sb.AppendLine("`n--- Dumps captured ---")
    Get-ChildItem $dumpDir -Filter "*.dmp" -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$sb.AppendLine("  $($_.Name) | $([math]::Round($_.Length/1MB,1))MB | $($_.LastWriteTime)")
    }
    $sb.ToString()
}

# Auto-dump when game stops responding
$watchdog = {
    param($dumpDir, $logFile)
    $hungDetected = $false
    while ($true) {
        Start-Sleep -Seconds 5
        $proc = Get-Process "Windrose-Win64-Shipping" -ErrorAction SilentlyContinue
        if ($proc -and -not $proc.Responding -and -not $hungDetected) {
            $hungDetected = $true
            $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
            "[$(Get-Date -Format 'HH:mm:ss')] !!! HANG DETECTED !!! Capturing dump..." | Out-File $logFile -Append

            # Capture dump
            $dmpFile = "$dumpDir\windrose_HANG_$ts.dmp"
            $pd = Get-Command procdump -ErrorAction SilentlyContinue
            if ($pd) {
                & procdump -ma -accepteula $proc.Id $dmpFile 2>&1 | Out-Null
            } else {
                cmd /c "rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump $($proc.Id) $dmpFile full" 2>&1 | Out-Null
            }

            # Log GPU events at time of hang
            $evtFile = "$dumpDir\events_HANG_$ts.txt"
            Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Display','nvlddmkm','dxgkrnl','dxgmms2'} -MaxEvents 20 -ErrorAction SilentlyContinue |
                Format-Table TimeCreated, ProviderName, Id, Message -Wrap | Out-File $evtFile

            "[$(Get-Date -Format 'HH:mm:ss')] Dump saved: $dmpFile" | Out-File $logFile -Append
        }
        if ($proc -and $proc.Responding) { $hungDetected = $false }
        if (-not $proc) { $hungDetected = $false }
    }
}

# Start watchdog in background
$job = Start-Job -ScriptBlock $watchdog -ArgumentList $dumpDir, $logFile
Log "Watchdog started (auto-captures dump on hang)"

# HTTP server
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$port/")
try { $listener.Start() } catch {
    # If port binding fails, try with firewall rule
    netsh advfirewall firewall add rule name="WindroseMonitor" dir=in action=allow protocol=tcp localport=$port | Out-Null
    $listener.Start()
}

Log "HTTP server listening on port $port"
Log "From your Mac:"
Log "  curl http://<this-ip>:$port/status"
Log "  curl http://<this-ip>:$port/diag"
Log "  curl http://<this-ip>:$port/events"
Log "  curl http://<this-ip>:$port/log"
Log ""
Log "Local IP(s):"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.PrefixOrigin -ne "WellKnown" } |
    ForEach-Object { Log "  $($_.IPAddress)" }
Log ""
Log "Waiting for requests... (Ctrl+C to stop)"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $path = $context.Request.Url.AbsolutePath.TrimEnd('/')
        $response = $context.Response
        $response.ContentType = "text/plain; charset=utf-8"

        $body = switch ($path) {
            "/status"  { Get-Status }
            "/diag"    { Get-Diag }
            "/events"  { Get-GpuEvents }
            "/log"     { if (Test-Path $logFile) { Get-Content $logFile -Raw } else { "No log yet" } }
            "/dump"    {
                # Trigger manual dump
                $proc = Get-Process "Windrose-Win64-Shipping" -ErrorAction SilentlyContinue
                if ($proc) {
                    $dmpFile = "$dumpDir\windrose_MANUAL_$(Get-Date -Format 'yyyyMMdd_HHmmss').dmp"
                    $pd = Get-Command procdump -ErrorAction SilentlyContinue
                    if ($pd) { & procdump -ma -accepteula $proc.Id $dmpFile 2>&1 | Out-Null }
                    else { cmd /c "rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump $($proc.Id) $dmpFile full" 2>&1 | Out-Null }
                    "Dump triggered: $dmpFile"
                } else { "Game not running" }
            }
            "/kill"    {
                Stop-Process -Name "Windrose-Win64-Shipping" -Force -ErrorAction SilentlyContinue
                "Game killed"
            }
            default    {
                "Windrose Monitor - Endpoints:`n  /status  - Game state + system overview`n  /diag    - Full diagnostics (GPU, TDR, drivers, Streamline)`n  /events  - GPU/Display event log`n  /log     - Monitor log (hang detections)`n  /dump    - Trigger manual dump`n  /kill    - Force kill game"
            }
        }

        $buffer = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
} finally {
    $listener.Stop()
    Stop-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -ErrorAction SilentlyContinue
    Log "Monitor stopped."
}
