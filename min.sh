#!/bin/bash

# Конфигурация
ETC_POOL="stratum+tcp://gate.emcd.network:7878"
ETC_WALLET="grammymurr.worker"
KASPA_POOL="stratum+tcp://gate.emcd.network:9999"
KASPA_WALLET="grammymurr.worker"

# Функция для проверки прав root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "❌ Запусти скрипт с правами root: sudo $0"
        exit 1
    fi
}

# Функция установки зависимостей
install_dependencies() {
    echo "📦 Проверяю зависимости..."
    if ! command -v wget &> /dev/null; then
        echo "📥 Устанавливаю wget..."
        apt-get update && apt-get install -y wget
    fi
}

# Установка и настройка lolMiner для ETC
install_etc_miner() {
    echo "📥 Устанавливаю lolMiner для ETC..."
    mkdir -p /opt/mining/etc
    cd /opt/mining/etc

    wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz
    if [ $? -ne 0 ]; then
        echo "❌ Ошибка загрузки lolMiner"
        exit 1
    fi

    tar -xzf lolMiner_v1.98_Lin64.tar.gz --strip-components=1
    rm -f lolMiner_v1.98_Lin64.tar.gz

    # Создаем скрипт запуска для ETC
    cat > /opt/mining/etc/start_etc_miner.sh << EOF
#!/bin/bash
cd /opt/mining/etc
./lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_WALLET --tls off --nocolor
EOF
    chmod +x /opt/mining/etc/start_etc_miner.sh
    echo "✅ lolMiner для ETC установлен и настроен"
}

# Установка и настройка SRBMiner для Kaspa
install_kaspa_miner() {
    echo "📥 Устанавливаю SRBMiner-MULTI для Kaspa..."
    mkdir -p /opt/mining/kaspa
    cd /opt/mining/kaspa

    # Скачиваем последнюю версию SRBMiner-MULTI для Linux
    wget -q https://github.com/doktor83/SRBMiner-Multi/releases/download/2.5.2/SRBMiner-Multi-2.5.2-Linux.tar.xz
    if [ $? -ne 0 ]; then
        echo "❌ Ошибка загрузки SRBMiner"
        exit 1
    fi

    tar -xf SRBMiner-Multi-2.5.2-Linux.tar.xz --strip-components=1
    rm -f SRBMiner-Multi-2.5.2-Linux.tar.xz
    chmod +x SRBMiner-MULTI

    # Создаем скрипт запуска для Kaspa (Stratum)
    cat > /opt/mining/kaspa/start_kaspa_miner.sh << EOF
#!/bin/bash
cd /opt/mining/kaspa
./SRBMiner-MULTI --algorithm kheavyhash --pool $KASPA_POOL --wallet $KASPA_WALLET --worker worker --gpu-boost 3
EOF
    chmod +x /opt/mining/kaspa/start_kaspa_miner.sh
    echo "✅ SRBMiner-MULTI для Kaspa установлен и настроен"
}

# Настройка автозапуска через systemd
setup_autostart() {
    echo "⏰ Настраиваю автозапуск через systemd..."

    # Создаем systemd сервис для ETC Miner
    cat > /etc/systemd/system/etc-miner.service << EOF
[Unit]
Description=ETC Mining Service
After=network.target

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

    # Создаем systemd сервис для Kaspa Miner
    cat > /etc/systemd/system/kaspa-miner.service << EOF
[Unit]
Description=Kaspa Mining Service
After=network.target

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

    echo "✅ Сервисы автозапуска настроены"
}

# Создание утилит управления
create_management_tools() {
    echo "🔧 Создаю утилиты управления..."

    cat > /usr/local/bin/start-mining.sh << 'EOF'
#!/bin/bash
echo "Запуск майнеров..."
systemctl start etc-miner.service
systemctl start kaspa-miner.service
echo "Майнеры запущены"
EOF

    cat > /usr/local/bin/stop-mining.sh << 'EOF'
#!/bin/bash
echo "Останавливаю майнеры..."
systemctl stop etc-miner.service
systemctl stop kaspa-miner.service
echo "Майнеры остановлены"
EOF

    cat > /usr/local/bin/mining-status.sh << 'EOF'
#!/bin/bash
echo "=== Статус майнеров ==="
echo "ETC Miner:"
systemctl is-active etc-miner.service && echo "✅ Запущен" || echo "❌ Не запущен"
echo ""
echo "Kaspa Miner:"
systemctl is-active kaspa-miner.service && echo "✅ Запущен" || echo "❌ Не запущен"
echo ""
echo "=== Логи ETC (последние 5 строк) ==="
journalctl -u etc-miner.service -n 5 --no-pager
echo ""
echo "=== Логи Kaspa (последние 5 строк) ==="
journalctl -u kaspa-miner.service -n 5 --no-pager
EOF

    chmod +x /usr/local/bin/start-mining.sh
    chmod +x /usr/local/bin/stop-mining.sh
    chmod +x /usr/local/bin/mining-status.sh

    echo "✅ Утилиты управления созданы"
}

# Запуск майнеров
start_miners() {
    echo "🚀 Запускаю майнеры..."
    systemctl daemon-reload
    systemctl start etc-miner.service
    systemctl start kaspa-miner.service
    echo "⏳ Ожидаю запуск (10 секунд)..."
    sleep 10
}

# Проверка установки
verify_installation() {
    echo ""
    echo "=== ПРОВЕРКА УСТАНОВКИ ==="
    echo "Файлы:"
    echo "ETC miner: $(ls -la /opt/mining/etc/lolMiner 2>/dev/null || echo 'НЕ НАЙДЕН')"
    echo "Kaspa miner: $(ls -la /opt/mining/kaspa/SRBMiner-MULTI 2>/dev/null || echo 'НЕ НАЙДЕН')"
    echo ""
    echo "Статус сервисов:"
    /usr/local/bin/mining-status.sh
}

# Главная функция
main() {
    check_root
    install_dependencies
    install_etc_miner
    install_kaspa_miner
    setup_autostart
    create_management_tools
    start_miners
    verify_installation

    echo ""
    echo "🎉 УСТАНОВКА ЗАВЕРШЕНА!"
    echo "📋 Команды управления:"
    echo "   start-mining.sh    - запустить майнеры"
    echo "   stop-mining.sh     - остановить майнеры"
    echo "   mining-status.sh   - проверить статус и логи"
    echo ""
    echo "💡 Майнеры настроены на автозапуск при загрузке системы"
}

# Запуск
main
