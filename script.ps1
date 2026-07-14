# ============================================================
# Backend Communication Tester
# ============================================================
# Simple terminal app to test the backend without serial port
# Sends the same JSON payload format as the FON Time Atack Interface
# ============================================================
 

# --- Config (edit here) ---
$backendUrl = "https://bcknd-fon-app.osnetpr.net/racelane/updateLast"

# --- Helpers ---
function Read-Required($prompt) {
    while ($true) {
        $val = Read-Host $prompt
        if (-not [string]::IsNullOrWhiteSpace($val)) { return $val.Trim() }
        Write-Host "  Value cannot be empty. Try again." -ForegroundColor Red
    }
}
 
function Read-Lane {
    while ($true) {
        $val = (Read-Host "Lane (L/R)").Trim().ToUpper()
        if ($val -eq "L" -or $val -eq "LEFT")  { return @{ Code = "L"; Name = "Left" } }
        if ($val -eq "R" -or $val -eq "RIGHT") { return @{ Code = "R"; Name = "Right" } }
        Write-Host "  Invalid. Enter L or R." -ForegroundColor Red
    }
}
 
function Read-Number($prompt, [switch]$AsInt) {
    while ($true) {
        $val = Read-Host $prompt
        $num = 0.0
        if ([double]::TryParse($val, [ref]$num)) {
            if ($AsInt) { return [int]$num }
            return $num
        }
        Write-Host "  Invalid number. Try again." -ForegroundColor Red
    }
}

function Format-ElapsedTime([double]$totalSeconds) {
    if ($totalSeconds -lt 0) { $totalSeconds = 0 }
    $hours   = [int][Math]::Floor($totalSeconds / 3600)
    $rem     = $totalSeconds - ($hours * 3600)
    $minutes = [int][Math]::Floor($rem / 60)
    $seconds = $rem - ($minutes * 60)
    $secInt  = [int][Math]::Floor($seconds)
    $ms      = [int][Math]::Round(($seconds - $secInt) * 1000)
    if ($ms -eq 1000) { $secInt++; $ms = 0 }
    return ('{0:D2}:{1:D2}:{2:D2}.{3:D3}' -f $hours, $minutes, $secInt, $ms)
}

function Read-Time($prompt) {
    while ($true) {
        $val = (Read-Host $prompt).Trim()
        if ([string]::IsNullOrWhiteSpace($val)) {
            Write-Host "  Value cannot be empty. Try again." -ForegroundColor Red
            continue
        }

        # Plain seconds fallback: 3.137
        $plain = 0.0
        if ($val -notmatch ':' -and [double]::TryParse($val, [ref]$plain) -and $plain -ge 0) {
            return Format-ElapsedTime $plain
        }

        # HH:MM:SS.MS — e.g. 00:00:03.137
        if ($val -match '^\d{1,2}:\d{1,2}:\d{1,2}(\.\d+)?$') {
            $parts   = $val -split ':'
            $hours   = [int]$parts[0]
            $minutes = [int]$parts[1]
            $seconds = 0.0
            if (-not [double]::TryParse($parts[2], [ref]$seconds)) {
                Write-Host "  Invalid time. Use HH:MM:SS.MS" -ForegroundColor Red
                continue
            }
            if ($minutes -ge 60 -or $seconds -ge 60) {
                Write-Host "  Minutes and seconds must be less than 60." -ForegroundColor Red
                continue
            }
            $totalSec = ($hours * 3600) + ($minutes * 60) + $seconds
            return Format-ElapsedTime $totalSec
        }

        Write-Host "  Invalid format. Use HH:MM:SS.MS (e.g. 00:00:03.137) or seconds (e.g. 3.137)" -ForegroundColor Red
    }
}
 
# ============================================================
# SETUP — collected ONCE at startup
# ============================================================
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Backend Communication Tester" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Enter the backend connection details:" -ForegroundColor Yellow
Write-Host ""
 
$eventID    = Read-Required "Event ID"
$authKey    = Read-Required "Authorization Key"
# $backendUrl = Read-Required "Backend URL"
 
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "  Config saved:" -ForegroundColor Green
Write-Host "    Event ID : $eventID"
Write-Host "    Auth Key : $('*' * $authKey.Length)"
Write-Host "    URL      : $backendUrl"
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
 
# ============================================================
# MAIN LOOP — send runs until user quits
# ============================================================
$sendCount = 0
 
while ($true) {
    Write-Host ""
    Write-Host "===  New Send  ===" -ForegroundColor Cyan
 
    # Lane + Time (Speed is always 0)
    $lane = Read-Lane
    $time = Read-Time "Time (seconds, e.g. 3.137)"
 
    # --- BUILD REQUEST (same format as v16) ---
    $headers = @{
        'Content-Type'  = 'application/json'
        'Authorization' = "Bearer $authKey"
    }
    $body = @{
        'RorL'  = $lane.Code
        'Speed' = 0.0
        'Event' = $eventID
        'Time'  = $time
    }
    $jsonBody = $body | ConvertTo-Json
 
    # --- SHOW WHAT WE'RE SENDING ---
    Write-Host ""
    Write-Host "  Sending..." -ForegroundColor Yellow
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host $jsonBody -ForegroundColor White
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
 
    # --- SEND ---
    try {
        $response = Invoke-RestMethod -Uri $backendUrl `
                                      -Method Patch `
                                      -Headers $headers `
                                      -Body $jsonBody `
                                      -TimeoutSec 10 `
                                      -ErrorAction Stop
 
        $sendCount++
        Write-Host "  [OK] Sent successfully  (total sent: $sendCount)" -ForegroundColor Green

        if ($null -ne $response) {
            Write-Host "  Backend response:" -ForegroundColor DarkGray
            Write-Host "  $($response | ConvertTo-Json -Compress)" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "  [FAIL] Send failed" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
 
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Host "  HTTP Status: $statusCode" -ForegroundColor Yellow
        }
    }
}
 
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Done. Total runs sent: $sendCount" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan