param(
    [Parameter(Mandatory = $true)]
    [string]$ClientDir,

    [int]$Port = 8100
)

$ErrorActionPreference = "Continue"

function Stop-ProcessIfAlive {
    param(
        [int]$ProcessId,
        [string]$Reason
    )

    if ($ProcessId -le 0 -or $ProcessId -eq $PID) {
        return
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        return
    }

    try {
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
        Write-Host "Stopped old local client runtime PID $ProcessId ($Reason)."
    } catch {
        Write-Host "Could not stop PID $ProcessId ($Reason): $($_.Exception.Message)"
    }
}

$pidPath = Join-Path $ClientDir "embedded_backend.pid"
if (Test-Path -LiteralPath $pidPath) {
    try {
        $raw = (Get-Content -LiteralPath $pidPath -Raw).Trim()
        $backendPid = [int]$raw
        Stop-ProcessIfAlive -ProcessId $backendPid -Reason "pid file"
    } catch {
        Write-Host "Old local client runtime PID cleanup skipped: $($_.Exception.Message)"
    }

    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

$listenerPids = @()
try {
    $listenerPids = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
        Select-Object -ExpandProperty OwningProcess -Unique
} catch {
    $netstatLines = netstat -ano -p tcp 2>$null | Select-String -Pattern "LISTENING"
    foreach ($line in $netstatLines) {
        $text = $line.ToString()
        if ($text -notmatch "[:\.]$Port\s+") {
            continue
        }
        $parts = $text -split "\s+" | Where-Object { $_ -ne "" }
        if ($parts.Count -gt 0) {
            $maybePid = 0
            if ([int]::TryParse($parts[-1], [ref]$maybePid)) {
                $listenerPids += $maybePid
            }
        }
    }
}

foreach ($listenerPid in ($listenerPids | Sort-Object -Unique)) {
    Stop-ProcessIfAlive -ProcessId ([int]$listenerPid) -Reason "port $Port listener"
}

Start-Sleep -Milliseconds 500
