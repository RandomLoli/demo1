#!/bin/bash

# =============================================================================
# 3X-UI Auto Installer with Telegram Notification
# Для массового развертывания на множестве серверов
# =============================================================================

# ⚙️ НАСТРОЙКИ TELEGRAM (ОБЯЗАТЕЛЬНО ЗАПОЛНИТЬ)
TG_TOKEN="ВАШ_ТОКЕН_БОТА"          # Пример: 6123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw
TG_CHAT="ВАШ_CHAT_ID"              # Пример: 123456789

# ⚙️ НАСТРОЙКИ ПАНЕЛИ
PANEL_PORT=""                      # Оставьте пустым для случайного порта или укажите свой (например, 54321)
PANEL_USER=""                      # Оставьте пустым для случайного логина
PANEL_PASS=""                      # Оставьте пустым для случайного пароля

# ⚙️ НАСТРОЙКИ СЕРВЕРА
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || hostname -I | awk '{print $1}')
SCRIPT_VERSION="1.0"

# =============================================================================
# ЦВЕТНОЙ ВЫВОД
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# ПРОВЕРКИ
# =============================================================================

# Проверка на root
if [[ $EUID -ne 0 ]]; then
    log_error "Запускайте скрипт от root (sudo -i)"
    exit 1
fi

# Проверка токена Telegram
if [[ "$TG_TOKEN" == "ВАШ_ТОКЕН_БОТА" ]] || [[ -z "$TG_TOKEN" ]]; then
    log_error "Не указан TG_TOKEN в скрипте!"
    exit 1
fi

if [[ -z "$TG_CHAT" ]]; then
    log_error "Не указан TG_CHAT в скрипте!"
    exit 1
fi

# Проверка на повторный запуск
if [[ -f "/etc/x-ui/x-ui.sh" ]]; then
    log_warn "Панель уже установлена. Отправляю текущие данные..."
    send_existing_data
    exit 0
fi

# =============================================================================
# ФУНКЦИИ
# =============================================================================

send_telegram() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
        -d chat_id="$TG_CHAT" \
        -d text="$message" \
        -d parse_mode="Markdown" \
        -d disable_web_page_preview="true" > /dev/null
}

send_existing_data() {
    local user=$(x-ui setting -show true 2>/dev/null | grep "username" | awk '{print $2}' | tr -d ',')
    local pass=$(x-ui setting -show true 2>/dev/null | grep "password" | awk '{print $2}' | tr -d ',')
    local port=$(x-ui setting -show true 2>/dev/null | grep "port" | awk '{print $2}' | tr -d ',')
    
    local msg="🔄 **3X-UI (уже установлен)**
🌐 IP: \`$SERVER_IP\`
👤 Login: \`$user\`
🔑 Pass: \`$pass\`
🚪 Port: \`$port\`
🔗 Link: \`http://$SERVER_IP:$port\`"
    
    send_telegram "$msg"
    log_success "Данные отправлены в Telegram"
}

generate_random() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $length | head -n 1
}

install_panel() {
    log_info "Начинаю установку 3X-UI..."
    
    # Экспорт переменных для скрипта установки
    export XUI_PORT=${PANEL_PORT:-$(shuf -i 10000-65000 -n 1)}
    export XUI_USER=${PANEL_USER:-$(generate_random 8)}
    export XUI_PASS=${PANEL_PASS:-$(generate_random 12)}
    
    # Скачивание и установка
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh) <<< $'\n'
    
    sleep 8
    
    # Принудительная установка настроек если не применились
    if [[ -n "$PANEL_PORT" ]]; then
        x-ui setting -port $PANEL_PORT 2>/dev/null
    fi
    if [[ -n "$PANEL_USER" ]]; then
        x-ui setting -username $PANEL_USER 2>/dev/null
    fi
    if [[ -n "$PANEL_PASS" ]]; then
        x-ui setting -password $PANEL_PASS 2>/dev/null
    fi
    
    # Перезапуск панели
    x-ui restart 2>/dev/null
    sleep 3
}

get_panel_data() {
    local user=$(x-ui setting -show true 2>/dev/null | grep "username" | awk '{print $2}' | tr -d ',')
    local pass=$(x-ui setting -show true 2>/dev/null | grep "password" | awk '{print $2}' | tr -d ',')
    local port=$(x-ui setting -show true 2>/dev/null | grep "port" | awk '{print $2}' | tr -d ',')
    
    echo "$user|$pass|$port"
}

send_install_report() {
    local status="$1"
    local data="$2"
    
    IFS='|' read -r user pass port <<< "$data"
    
    if [[ "$status" == "success" ]]; then
        local msg="✅ **3X-UI Успешно**
━━━━━━━━━━━━━━━━━━━━
🖥 Server: \`$SERVER_IP\`
👤 Login: \`$user\`
🔑 Pass: \`$pass\`
🚪 Port: \`$port\`
━━━━━━━━━━━━━━━━━━━━
🔗 Web: \`http://$SERVER_IP:$port\`
📅 Date: \`$(date '+%Y-%m-%d %H:%M')\`
⚠️ _Удалите после входа!_"
    else
        local msg="❌ **3X-UI Ошибка**
━━━━━━━━━━━━━━━━━━━━
🖥 Server: \`$SERVER_IP\`
⚠️ Status: \`FAILED\`
📅 Date: \`$(date '+%Y-%m-%d %H:%M')\`"
    fi
    
    send_telegram "$msg"
}

# =============================================================================
# ОСНОВНОЙ ЗАПУСК
# =============================================================================

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║     3X-UI Auto Installer v$SCRIPT_VERSION          ║"
echo "╚════════════════════════════════════════════╝"
echo ""

log_info "Server IP: $SERVER_IP"
log_info "Telegram Chat: $TG_CHAT"

# Тест связи с Telegram
log_info "Проверка связи с Telegram..."
test_msg=$(curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    -d text="🔧 **3X-UI Installer**
Тест связи с сервером: \`$SERVER_IP\`" \
    -d parse_mode="Markdown")

if echo "$test_msg" | grep -q '"ok":true'; then
    log_success "Telegram доступен"
else
    log_warn "Не удалось отправить тестовое сообщение в Telegram"
fi

# Установка
install_panel

# Получение данных
panel_data=$(get_panel_data)

if [[ -n "$panel_data" ]]; then
    log_success "Панель установлена"
    send_install_report "success" "$panel_data"
else
    log_error "Не удалось получить данные панели"
    send_install_report "error" "||"
fi

# Очистка истории
history -c 2>/dev/null
history -w 2>/dev/null

echo ""
log_success "Готово! Проверьте Telegram"
echo ""
