# tg_test.ps1 — минимальный тест
$TG_TOKEN = "5466273638:AAF5XEp-3IIgjsgOlV2YauFeSnBlAZeFe5M"
$TG_CHAT = "5336452267"
$HOST = $env:COMPUTERNAME

Write-Host "=== TELEGRAM TEST ==="
Write-Host "Host: $HOST"
Write-Host "Token: $TG_TOKEN"
Write-Host "Chat: $TG_CHAT"

# 1. Проверка сети
Write-Host "`n[1] Проверка сети..."
try {
    $ping = Test-Connection -ComputerName "api.telegram.org" -Count 1 -Quiet
    Write-Host "Ping Telegram: $ping"
    if (-not $ping) {
        Write-Host "❌ НЕТ ДОСТУПА К TELEGRAM API" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "❌ Ошибка ping: $_" -ForegroundColor Red
    exit 1
}

# 2. Тест через curl.exe (если есть)
Write-Host "`n[2] Тест через curl.exe..."
if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    $msg = "🧪 CURL TEST от $HOST"
    $body = @{chat_id=$TG_CHAT; text=$msg; parse_mode="HTML"} | ConvertTo-Json -Compress
    $result = curl.exe -s -k -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" `
        -H "Content-Type: application/json" -d $body -w "\nHTTP_CODE:%{http_code}"
    Write-Host "Result: $result"
    if ($result -like "*HTTP_CODE:200*") {
        Write-Host "✅ CURL: OK" -ForegroundColor Green
    } else {
        Write-Host "❌ CURL: FAILED" -ForegroundColor Red
    }
} else {
    Write-Host "⚠️ curl.exe не найден"
}

# 3. Тест через Invoke-RestMethod
Write-Host "`n[3] Тест через Invoke-RestMethod..."
try {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    $msg = "🧪 PowerShell TEST от $HOST"
    $body = @{chat_id=$TG_CHAT; text=$msg; parse_mode="HTML"} | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Uri "https://api.telegram.org/bot$TG_TOKEN/sendMessage" `
        -Method Post -ContentType "application/json" -Body $body -TimeoutSec 10
    Write-Host "Response: $($resp.ok)" -ForegroundColor Green
    Write-Host "✅ PowerShell: OK" -ForegroundColor Green
} catch {
    Write-Host "❌ PowerShell: $_" -ForegroundColor Red
}

Write-Host "`n=== TEST COMPLETE ==="
