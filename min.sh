#!/bin/bash

# Конфигурация
ETC_POOL="stratum+tcp://gate.emcd.network:7878"
ETC_WALLET="grammymurr.worker"
KASPA_POOL="gate.emcd.network"
KASPA_PORT="9999"
KASPA_WALLET="grammymurr.worker"

# Telegram уведомления (раскомментируй и настрой)
# BOT_TOKEN="твой_токен_бота"
# CHAT_ID="твой_чат_id"

# Функция для Telegram уведомлений
send_telegram_msg() {
    local message="$1"
    # Раскомментируй после настройки Telegram:
    # curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    #     -d "chat_id=${CHAT_ID}" \
    #     -d "text=${message}" \
    #     -d "parse_mode=HTML" > /dev/null
    echo "Telegram: $message"
}

# Проверка прав root
if [ $EUID -ne 0 ]; then
    echo "❌ Запусти скрипт с правами root: sudo $0"
    exit 1
fi

echo "🔄 Начинаю установку майнеров..."

# Создаем директории (принудительно)
mkdir -p /opt/mining/etc
mkdir -p /opt/mining/kaspa
cd /opt/mining

# Установка lolMiner для ETC
echo "📥 Устанавливаю lolMiner для ETC..."
wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz
if [ $? -ne 0 ]; then
    echo "❌ Ошибка загрузки lolMiner"
    exit 1
fi

tar -xzf lolMiner_v1.98_Lin64.tar.gz -C /opt/mining/etc/ --strip-components=1
rm -f lolMiner_v1.98_Lin64.tar.gz

# Создаем скрипт запуска для ETC
cat > /opt/mining/etc/start_etc_miner.sh << EOF
#!/bin/bash
cd /opt/mining/etc
./lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_WALLET --tls off --nocolor
EOF

chmod +x /opt/mining/etc/start_etc_miner.sh

# Установка Kaspa Miner
echo "📥 Устанавливаю Kaspa miner..."
cd /opt/mining/kaspa
wget -q https://github.com/tmrlvi/kaspa-miner/releases/download/v0.2.1-GPU-0.7/kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
if [ $? -ne 0 ]; then
    echo "❌ Ошибка загрузки Kaspa miner"
    exit 1
fi

tar -xzf kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
mv kaspa-miner* kaspa-miner 2>/dev/null || true
rm -f kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz

# Создаем скрипт запуска для Kaspa
cat > /opt/mining/kaspa/start_kaspa_miner.sh << EOF
#!/bin/bash
cd /opt/mining/kaspa
./kaspa-miner --mining-address $KASPA_WALLET --kaspad-address $KASPA_POOL --port $KASPA_PORT
EOF

chmod +x /opt/mining/kaspa/start_kaspa_miner.sh

# Настройка автозапуска через cron
echo "⏰ Настраиваю автозапуск через cron..."
(crontab -l 2>/dev/null | grep -v "start_etc_miner.sh"; echo "@reboot /opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1") | crontab -
(crontab -l 2>/dev/null | grep -v "start_kaspa_miner.sh"; echo "@reboot /opt/mining/kaspa/start_kaspa_miner.sh > /var/log/kaspa-miner.log 2>&1") | crontab -

# Создаем скрипты для ручного управления
cat > /usr/local/bin/start-mining.sh << 'EOF'
#!/bin/bash
echo "Запуск майнеров..."
/opt/mining/etc/start_etc_miner.sh &
/opt/mining/kaspa/start_kaspa_miner.sh &
echo "Майнеры запущены в фоне"
echo "Логи ETC: /var/log/etc-miner.log"
echo "Логи Kaspa: /var/log/kaspa-miner.log"
EOF

cat > /usr/local/bin/stop-mining.sh << 'EOF'
#!/bin/bash
echo "Останавливаю майнеры..."
pkill -f lolMiner
pkill -f kaspa-miner
echo "Майнеры остановлены"
EOF

cat > /usr/local/bin/mining-status.sh << 'EOF'
#!/bin/bash
echo "=== Статус майнеров ==="
echo "ETC Miner:"
pgrep -f lolMiner && echo "✅ Запущен" || echo "❌ Не запущен"
echo ""
echo "Kaspa Miner:"
pgrep -f kaspa-miner && echo "✅ Запущен" || echo "❌ Не запущен"
echo ""
echo "Логи ETC (последние 10 строк):"
tail -10 /var/log/etc-miner.log 2>/dev/null || echo "Файл лога не найден"
echo ""
echo "Логи Kaspa (последние 10 строк):"
tail -10 /var/log/kaspa-miner.log 2>/dev/null || echo "Файл лога не найден"
EOF

chmod +x /usr/local/bin/start-mining.sh
chmod +x /usr/local/bin/stop-mining.sh
chmod +x /usr/local/bin/mining-status.sh

# Запускаем майнеры
echo "🚀 Запускаю майнеры..."
/opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &
/opt/mining/kaspa/start_kaspa_miner.sh > /var/log/kaspa-miner.log 2>&1 &

echo "✅ Установка завершена!"
echo ""
echo "📋 Команды для управления:"
echo "   start-mining.sh    - запустить майнеры"
echo "   stop-mining.sh     - остановить майнеры" 
echo "   mining-status.sh   - проверить статус"
echo ""
echo "📊 Проверяю запуск..."
sleep 5

# Проверяем запуск
echo ""
echo "=== ПРОВЕРКА ЗАПУСКА ==="
/usr/local/bin/mining-status.sh

# Отправляем уведомление
send_telegram_msg "✅ Майнеры успешно установлены на сервере $(hostname)
• ETC Miner: $ETC_POOL
• Kaspa Miner: $KASPA_POOL:$KASPA_PORT
• Автозапуск настроен через cron
Команды управления: start-mining.sh, stop-mining.sh, mining-status.sh"

echo ""
echo "💡 Майнеры настроены на автозапуск при перезагрузке системы"
echo "🔍 Логи пишутся в: /var/log/etc-miner.log и /var/log/kaspa-miner.log"
