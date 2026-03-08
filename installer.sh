<#
MINING AGENT — WINDOWS DEBUG EDITION
Отладка: всё логируется в ТГ + файл
#>
param([switch]$Debug)

# ===== НАСТРОЙКИ =====
$TG_TOKEN = "5466273638:AAF5XEp-3IIgjsgOlV2YauFeSnBlAZeFe5M"
$TG_CHAT = "5336452267"
$HOST = $env:COMPUTERNAME
$IP = (Test-Connection -ComputerName 1.1.1.1 -Count 1 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPv4Address) -or "0.0.0.0"
$LOG = "$env:TEMP\mining_debug.log"

function Tg { param($M)
    try {
        $body = @{chat_id=$TG_CHAT; text="🪟 $HOST ($IP)`n$M"; parse_mode="HTML"} | ConvertTo-Json
        if (Get-Command curl.exe -ea 0) {
            curl.exe -s -k -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -H "Content-Type: application/json" -d $body | Out-Null
        } else {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 10 -ea 0 | Out-Null
        }
    } catch { Add-Content $LOG "TG FAIL: $_" }
}

function Log { param($M) $ts = Get-Date -Format "HH:mm:ss"; Add-Content $LOG "[$ts] $M"; if($Debug){Write-Host "[$ts] $M"} }

# ===== START =====
Log "=== AGENT START ==="
Tg "🟢 Запуск отладки на $HOST"

# 1. Проверка окружения
Log "PS: $($PSVersionTable.PSVersion.ToString())"
Log "Curl: $((Get-Command curl.exe -ea 0) -ne $null)"
Log "ExecPolicy: $(Get-ExecutionPolicy -Scope CurrentUser)"

# 2. Проверка сети
if (-not (Test-Connection -ComputerName api.telegram.org -Count 1 -Quiet)) {
    Log "❌ НЕТ ДОСТУПА К ИНТЕРНЕТУ (Telegram)"; Tg "❌ Нет сети на $HOST"; exit 1
}
Log "✅ Сеть OK"

# 3. Проверка флага
if ($env:ALLOW_MINING -ne "1") {
    Log "⚠️ ALLOW_MINING != 1, выход"; Tg "⚠️ ALLOW_MINING не установлен на $HOST"; exit 0
}
Log "✅ ALLOW_MINING=1"

# 4. Пути
$BASE = "$env:USERPROFILE\.mining"
Log "BASE: $BASE"
try {
    New-Item -Path "$BASE\bin\cpu","$BASE\bin\gpu","$BASE\run","$BASE\log" -ItemType Directory -Force -ea 0 | Out-Null
    Log "✅ Папки созданы"
} catch {
    Log "❌ Ошибка создания папок: $_"; Tg "❌ Не создать папки: $_"; exit 1
}

# 5. Тест скачивания XMRig
Log "📦 Тест загрузки XMRig..."
$url = "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-msvc-win64.zip"
$tmp = "$env:TEMP\xmrig_test.zip"
try {
    if (Get-Command curl.exe -ea 0) {
        curl.exe -s -k -L $url -o $tmp --connect-timeout 10 --max-time 30
    } else {
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 30
    }
    if (Test-Path $tmp -and (Get-Item $tmp).Length -gt 100000) {
        Log "✅ XMRig скачан ($(Get-Item $tmp).Length байт)"
        Remove-Item $tmp -Force
    } else {
        Log "❌ XMRig скачан битый или пустой"
        Tg "❌ XMRig download fail на $HOST"
    }
} catch {
    Log "❌ Ошибка загрузки: $_"
    Tg "❌ Download error: $_"
}

# 6. Финал
Log "=== DEBUG COMPLETE ==="
Tg "✅ Отладка завершена на $HOST`nЛог: $LOG"
exit 0
