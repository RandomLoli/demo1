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
if [ "$EUID" -ne 0 ]; then
    echo "❌ Запусти скрипт с правами root: sudo $0"
    exit 1
fi

echo "🔄 Начинаю установку майнеров..."

# Создаем директории
mkdir -p /opt/mining/{etc,kaspa}
cd /opt/mining

# Установка lolMiner для ETC
echo "📥 Устанавливаю lolMiner для ETC..."
wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz
if [ $? -ne 0 ]; then
    echo "❌ Ошибка загрузки lolMiner"
    exit 1
fi

tar -xzf lolMiner_v1.98_Lin64.tar.gz
mv 1.98/* /opt/mining/etc/
rm -rf lolMiner_v1.98_Lin64.tar.gz 1.98

# Создаем скрипт запуска для ETC
cat > /opt/mining/etc/start_etc_miner.sh << EOF
#!/bin/bash
cd /opt/mining/etc
./lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_WALLET --tls off --nocolor
EOF

chmod +x /opt/mining/etc/start_etc_miner.sh

# Установка Kaspa Miner
echo "📥 Устанавливаю Kaspa miner..."
wget -q https://github.com/tmrlvi/kaspa-miner/releases/download/v0.2.1-GPU-0.7/kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
if [ $? -ne 0 ]; then
    echo "❌ Ошибка загрузки Kaspa miner"
    exit 1
fi

tar -xzf kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
mv kaspa-miner /opt/mining/kaspa/
rm -f kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz

# Создаем скрипт запуска для Kaspa
cat > /opt/mining/kaspa/start_kaspa_miner.sh << EOF
#!/bin/bash
cd /opt/mining/kaspa
./kaspa-miner --mining-address $KASPA_WALLET --kaspad-address $KASPA_POOL --port $KASPA_PORT
EOF

chmod +x /opt/mining/kaspa/start_kaspa_miner.sh

# Создаем systemd сервис для ETC
cat > /etc/systemd/system/etc-miner.service << EOF
[Unit]
Description=ETC Mining Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mining/etc
ExecStart=/opt/mining/etc/start_etc_miner.sh
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Создаем systemd сервис для Kaspa
cat > /etc/systemd/system/kaspa-miner.service << EOF
[Unit]
Description=Kaspa Mining Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/mining/kaspa
ExecStart=/opt/mining/kaspa/start_kaspa_miner.sh
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем systemd и включаем сервисы
systemctl daemon-reload
systemctl enable etc-miner.service
systemctl enable kaspa-miner.service

# Запускаем сервисы
echo "🚀 Запускаю майнеры..."
systemctl start etc-miner.service
systemctl start kaspa-miner.service

echo "✅ Установка завершена!"
echo "📊 Статус ETC майнера: systemctl status etc-miner.service"
echo "📊 Статус Kaspa майнера: systemctl status kaspa-miner.service"

# Отправляем уведомление
send_telegram_msg "✅ Майнеры успешно установлены на сервере $(hostname)
• ETC Miner: $ETC_POOL
• Kaspa Miner: $KASPA_POOL:$KASPA_PORT
Сервисы настроены на автозапуск при перезагрузке."

# Проверяем статус сервисов
sleep 10
echo ""
echo "=== СТАТУС СЕРВИСОВ ==="
echo "ETC Miner:"
systemctl is-active etc-miner.service && echo "✅ Запущен" || echo "❌ Не запущен"

echo "Kaspa Miner:"
systemctl is-active kaspa-miner.service && echo "✅ Запущен" || echo "❌ Не запущен"

echo ""
echo "🔍 Для просмотра логов используй:"
echo "ETC: journalctl -u etc-miner.service -f"
echo "Kaspa: journalctl -u kaspa-miner.service -f"
