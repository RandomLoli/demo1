#!/bin/bash

# Конфигурация для Kryptex
KRIPTEX_USERNAME="krxX3PVQVR"  # ЗАМЕНИТЕ на ваш логин Kryptex
WORKER_NAME="worker"            # Имя воркера

# Конфигурация Telegram бота
TELEGRAM_BOT_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TELEGRAM_CHAT_ID="5336452267"

# Пул и порты Kryptex
ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

# Формируем логины для пула
ETC_USERNAME="$KRIPTEX_USERNAME.$WORKER_NAME"
XMR_USERNAME="$KRIPTEX_USERNAME.$WORKER_NAME"

# Функция отправки сообщения в Telegram
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null
}

# Функция получения IP-адреса сервера
get_server_ip() {
    curl -s -4 ifconfig.me || curl -s -6 ifconfig.me || echo "unknown"
}

# Функция получения скорости майнинга
get_mining_speed() {
    local etc_speed="нет данных"
    local xmr_speed="нет данных"
    
    # Получаем скорость ETC майнера
    if [ -f "/var/log/etc-miner.log" ]; then
        etc_speed=$(tail -50 /var/log/etc-miner.log 2>/dev/null | grep -o "Average speed.*" | tail -1 | sed 's/Average speed://g' | xargs || echo "нет данных")
    fi
    
    # Получаем скорость XMR майнера
    if [ -f "/var/log/xmr-miner.log" ]; then
        xmr_speed=$(tail -50 /var/log/xmr-miner.log 2>/dev/null | grep -o "speed.*H/s" | tail -1 | sed 's/speed.*max//g' | xargs || echo "нет данных")
    fi
    
    echo "ETC: $etc_speed | XMR: $xmr_speed"
}

# Функция для отправки статуса майнинга
send_mining_status() {
    local server_ip=$(get_server_ip)
    local mining_speed=$(get_mining_speed)
    
    local status_msg="📊 <b>Статус майнинга</b>
🖥️ Хост: <code>$(hostname)</code>
🌐 IP: <code>${server_ip}</code>
⚡ Скорость: ${mining_speed}
⏰ Время: <code>$(date)</code>"
    
    send_telegram_message "$status_msg"
}

# Функции для проверки прав и зависимостей
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ Запустите скрипт с правами root: sudo $0"
        exit 1
    fi
}

install_dependencies() {
    echo "📦 Проверяю и устанавливаю зависимости..."
    if ! command -v wget &> /dev/null; then
        echo "📥 Устанавливаю wget..."
        apt-get update && apt-get install -y wget curl
    fi
    if ! command -v crontab &> /dev/null; then
        echo "📥 Устанавливаю cron..."
        apt-get update && apt-get install -y cron
    fi
    if ! command -v curl &> /dev/null; then
        echo "📥 Устанавливаю curl..."
        apt-get update && apt-get install -y curl
    fi
}

# Установка lolMiner для ETC (GPU)
install_etc_miner() {
    echo "📥 Устанавливаю lolMiner для ETC..."
    mkdir -p /opt/mining/etc
    cd /opt/mining/etc

    if wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz; then
        tar -xzf lolMiner_v1.98_Lin64.tar.gz --strip-components=1
        rm -f lolMiner_v1.98_Lin64.tar.gz
        
        # Создаем скрипт запуска для ETC
        cat > /opt/mining/etc/start_etc_miner.sh << EOF
#!/bin/bash
cd /opt/mining/etc
./lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_USERNAME --tls off --nocolor
EOF
        chmod +x /opt/mining/etc/start_etc_miner.sh
        echo "✅ lolMiner для ETC установлен и настроен"
        return 0
    else
        echo "❌ Ошибка загрузки lolMiner"
        return 1
    fi
}

# Установка XMRig для Monero (CPU) - с исправленными параметрами
install_xmr_miner() {
    echo "📥 Устанавливаю XMRig для Monero..."
    mkdir -p /opt/mining/xmr
    cd /opt/mining/xmr

    # Скачиваем и распаковываем XMRig
    if wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz; then
        tar -xzf xmrig-*-linux-x64.tar.gz --strip-components=1
        rm -f xmrig-*-linux-x64.tar.gz

        # Исправленный скрипт запуска для XMR
        cat > /opt/mining/xmr/start_xmr_miner.sh << EOF
#!/bin/bash
cd /opt/mining/xmr
./xmrig -o $XMR_POOL -u $XMR_USERNAME -p x --randomx-1gb-pages
EOF
        chmod +x /opt/mining/xmr/start_xmr_miner.sh
        echo "✅ XMRig для Monero установлен и настроен"
        return 0
    else
        echo "❌ Ошибка загрузки XMRig"
        return 1
    fi
}

# Настройка автозапуска через cron
setup_autostart() {
    echo "⏰ Настраиваю автозапуск через cron..."
    (crontab -l 2>/dev/null | grep -v "/opt/mining/etc/start_etc_miner.sh"; echo "@reboot /opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &") | crontab -
    (crontab -l 2>/dev/null | grep -v "/opt/mining/xmr/start_xmr_miner.sh"; echo "@reboot /opt/mining/xmr/start_xmr_miner.sh > /var/log/xmr-miner.log 2>&1 &") | crontab -
    
    # Настраиваем периодические отчеты каждые 15 минут
    (crontab -l 2>/dev/null | grep -v "/opt/mining/scripts/report.sh"; echo "*/15 * * * * /opt/mining/scripts/report.sh > /dev/null 2>&1") | crontab -
    
    echo "✅ Автозапуск через cron настроен"
}

# Создание утилит управления
create_management_tools() {
    echo "🔧 Создаю утилиты управления..."

    cat > /usr/local/bin/start-mining.sh << EOF
#!/bin/bash
echo "Запуск майнеров..."
/opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &
/opt/mining/xmr/start_xmr_miner.sh > /var/log/xmr-miner.log 2>&1 &
echo "✅ Майнеры запущены в фоне"

# Отправляем уведомление в Telegram
SERVER_IP=\$(curl -s -4 ifconfig.me || curl -s -6 ifconfig.me || echo "unknown")
START_MSG="🚀 <b>Майнеры запущены</b>
🖥️ Хост: <code>\$(hostname)</code>
🌐 IP сервера: <code>\${SERVER_IP}</code>
⏰ Время: <code>\$(date)</code>"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=\${START_MSG}" \
    -d "parse_mode=HTML" > /dev/null
EOF

    cat > /usr/local/bin/stop-mining.sh << 'EOF'
#!/bin/bash
echo "Останавливаю майнеры..."
pkill -f "lolMiner.*ETCHASH"
pkill -f xmrig
sleep 2
# Принудительное завершение если процессы еще остались
pkill -9 -f "lolMiner.*ETCHASH" 2>/dev/null
pkill -9 -f xmrig 2>/dev/null
echo "✅ Майнеры остановлены"
EOF

    cat > /usr/local/bin/mining-status.sh << 'EOF'
#!/bin/bash
echo "=== Статус майнеров ==="
if pgrep -f "lolMiner.*ETCHASH" > /dev/null; then
    echo "✅ ETC Miner (GPU): Запущен (PID: $(pgrep -f 'lolMiner.*ETCHASH'))"
else
    echo "❌ ETC Miner (GPU): Не запущен"
fi
if pgrep -f xmrig > /dev/null; then
    echo "✅ XMR Miner (CPU): Запущен (PID: $(pgrep -f xmrig))"
else
    echo "❌ XMR Miner (CPU): Не запущен"
fi
echo ""
echo "=== Логи ETC (последние 3 строки) ==="
tail -3 /var/log/etc-miner.log 2>/dev/null || echo "Лог ETC пуст или отсутствует"
echo ""
echo "=== Логи XMR (последние 3 строки) ==="
tail -3 /var/log/xmr-miner.log 2>/dev/null || echo "Лог XMR пуст или отсутствует"
EOF

    # Создаем скрипт для отчетов
    mkdir -p /opt/mining/scripts
    cat > /opt/mining/scripts/report.sh << EOF
#!/bin/bash
# Конфигурация Telegram
TELEGRAM_BOT_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TELEGRAM_CHAT_ID="5336452267"

# Функция отправки сообщения
send_telegram_message() {
    local message="\$1"
    curl -s -X POST "https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/sendMessage" \\
        -d "chat_id=\${TELEGRAM_CHAT_ID}" \\
        -d "text=\${message}" \\
        -d "parse_mode=HTML" > /dev/null
}

# Функция получения IP
get_server_ip() {
    curl -s -4 ifconfig.me || curl -s -6 ifconfig.me || echo "unknown"
}

# Функция получения скорости майнинга
get_mining_speed() {
    local etc_speed="нет данных"
    local xmr_speed="нет данных"
    
    # Получаем скорость ETC майнера
    if [ -f "/var/log/etc-miner.log" ]; then
        etc_speed=\$(tail -50 /var/log/etc-miner.log 2>/dev/null | grep -o "Average speed.*" | tail -1 | sed 's/Average speed://g' | xargs || echo "нет данных")
    fi
    
    # Получаем скорость XMR майнера
    if [ -f "/var/log/xmr-miner.log" ]; then
        xmr_speed=\$(tail -50 /var/log/xmr-miner.log 2>/dev/null | grep -o "speed.*H/s" | tail -1 | sed 's/speed.*max//g' | xargs || echo "нет данных")
    fi
    
    echo "ETC: \$etc_speed | XMR: \$xmr_speed"
}

# Собираем информацию
SERVER_IP=\$(get_server_ip)
MINING_SPEED=\$(get_mining_speed)

# Формируем отчет
REPORT_MSG="📊 <b>Авто-отчет майнинга</b>
🖥️ Хост: <code>\$(hostname)</code>
🌐 IP: <code>\${SERVER_IP}</code>
⚡ Скорость: \${MINING_SPEED}
⏰ Время: <code>\$(date)</code>"

# Отправляем отчет
send_telegram_message "\$REPORT_MSG"
EOF

    chmod +x /usr/local/bin/start-mining.sh
    chmod +x /usr/local/bin/stop-mining.sh
    chmod +x /usr/local/bin/mining-status.sh
    chmod +x /opt/mining/scripts/report.sh
    
    echo "✅ Утилиты управления созданы"
}

# Главная функция
main() {
    check_root
    
    # Отправляем уведомление о начале установки
    SERVER_IP=$(get_server_ip)
    INSTALL_START_MSG="🔄 <b>Начало установки майнеров</b>
🖥️ Хост: <code>$(hostname)</code>
🌐 IP сервера: <code>${SERVER_IP}</code>
⏰ Время: <code>$(date)</code>"
    send_telegram_message "$INSTALL_START_MSG"
    
    install_dependencies

    if install_etc_miner; then
        echo "✅ ETC майнер установлен"
    else
        echo "❌ Ошибка установки ETC майнера"
        send_telegram_message "❌ <b>Ошибка установки ETC майнера</b>"
    fi
    
    if install_xmr_miner; then
        echo "✅ XMR майнер установлен"
    else
        echo "❌ Ошибка установки XMR майнера"
        send_telegram_message "❌ <b>Ошибка установки XMR майнера</b>"
    fi

    setup_autostart
    create_management_tools

    echo "🚀 Запускаю майнеры..."
    /usr/local/bin/stop-mining.sh > /dev/null 2>&1
    sleep 3
    /usr/local/bin/start-mining.sh
    sleep 5

    # Отправляем уведомление об успешной установке
    SERVER_IP=$(get_server_ip)
    INSTALL_COMPLETE_MSG="🎉 <b>Установка майнеров завершена</b>
🖥️ Хост: <code>$(hostname)</code>
🌐 IP сервера: <code>${SERVER_IP}</code>
⛏️ Майнеры: ETC (GPU) + XMR (CPU)
📊 Отчеты: каждые 15 минут
⏰ Время: <code>$(date)</code>"
    send_telegram_message "$INSTALL_COMPLETE_MSG"

    echo ""
    echo "🎉 НАСТРОЙКА ЗАВЕРШЕНА!"
    echo "📊 Статус:"
    /usr/local/bin/mining-status.sh

    # Отправляем первый отчет
    send_mining_status

    echo ""
    echo "📋 Команды управления:"
    echo "   start-mining.sh    - запустить майнеры"
    echo "   stop-mining.sh     - остановить майнеры"
    echo "   mining-status.sh   - проверить статус и логи"
    echo ""
    echo "💡 Майнеры настроены на автозапуск при перезагрузке"
    echo "📈 Авто-отчеты будут приходить каждые 15 минут"
}

# Запуск
main
