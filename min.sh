#!/bin/bash

# Конфигурация
ETC_POOL="stratum+tcp://gate.emcd.network:7878"
ETC_WALLET="grammymurr.worker"
KASPA_POOL="gate.emcd.network"
KASPA_PORT="9999"
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
    
    # Проверяем наличие wget
    if ! command -v wget &> /dev/null; then
        echo "📥 Устанавливаю wget..."
        apt-get update && apt-get install -y wget
    fi
    
    # Проверяем наличие cron
    if ! command -v crontab &> /dev/null; then
        echo "📥 Устанавливаю cron..."
        apt-get update && apt-get install -y cron
        # Запускаем cron через service вместо systemctl
        if command -v service &> /dev/null; then
            service cron start
        else
            /etc/init.d/cron start
        fi
    fi
}

# Функция для создания автозапуска
setup_autostart() {
    echo "⏰ Настраиваю автозапуск..."
    
    # Создаем init скрипт для автозапуска
    cat > /etc/init.d/mining-start << 'EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          mining-start
# Required-Start:    $local_fs $network
# Required-Stop:     $local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start mining on boot
# Description:       Start ETC and Kaspa miners on system boot
### END INIT INFO

case "$1" in
    start)
        echo "Starting miners..."
        /opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &
        /opt/mining/kaspa/start_kaspa_miner.sh > /var/log/kaspa-miner.log 2>&1 &
        ;;
    stop)
        echo "Stopping miners..."
        pkill -f lolMiner
        pkill -f kaspa-miner
        ;;
    restart)
        $0 stop
        sleep 5
        $0 start
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF

    chmod +x /etc/init.d/mining-start
    if command -v update-rc.d &> /dev/null; then
        update-rc.d mining-start defaults
    fi
    
    # Также настраиваем через cron для надежности
    (crontab -l 2>/dev/null | grep -v "start_etc_miner.sh"; echo "@reboot /opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1") | crontab -
    (crontab -l 2>/dev/null | grep -v "start_kaspa_miner.sh"; echo "@reboot /opt/mining/kaspa/start_kaspa_miner.sh > /var/log/kaspa-miner.log 2>&1") | crontab -
}

# Основная установка
main_install() {
    echo "🔄 Начинаю установку майнеров..."
    
    # Создаем директории
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

    # Установка Kaspa Miner - ИСПРАВЛЕННАЯ ВЕРСИЯ
    echo "📥 Устанавливаю Kaspa miner..."
    cd /opt/mining/kaspa
    wget -q https://github.com/tmrlvi/kaspa-miner/releases/download/v0.2.1-GPU-0.7/kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
    if [ $? -ne 0 ]; then
        echo "❌ Ошибка загрузки Kaspa miner"
        exit 1
    fi

    # Распаковываем архив
    tar -xzf kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
    
    # Переходим в распакованную директорию и находим бинарник
    cd kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64
    
    # Находим и копируем бинарник kaspa-miner
    KASPA_BINARY=$(find . -name "kaspa-miner*" -type f ! -name "*.so" ! -name "*.tgz" | head -1)
    if [ -n "$KASPA_BINARY" ] && [ -f "$KASPA_BINARY" ]; then
        cp "$KASPA_BINARY" ../kaspa-miner
        echo "✅ Бинарник Kaspa найден: $KASPA_BINARY"
    else
        echo "❌ Не могу найти бинарник Kaspa miner"
        echo "Содержимое директории:"
        ls -la
        exit 1
    fi
    
    # Копируем библиотеки
    cp libkaspaopencl.so ../ 2>/dev/null || echo "⚠️ libkaspaopencl.so не найден"
    cp libkaspacuda.so ../ 2>/dev/null || echo "⚠️ libkaspacuda.so не найден"
    
    # Возвращаемся и чистим
    cd ..
    rm -rf kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64
    rm -f kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
    
    chmod +x kaspa-miner

    # Создаем скрипт запуска для Kaspa
    cat > /opt/mining/kaspa/start_kaspa_miner.sh << EOF
#!/bin/bash
cd /opt/mining/kaspa
./kaspa-miner --mining-address $KASPA_WALLET --kaspad-address $KASPA_POOL --port $KASPA_PORT
EOF

    chmod +x /opt/mining/kaspa/start_kaspa_miner.sh
}

# Создание утилит управления
create_management_tools() {
    echo "🔧 Создаю утилиты управления..."
    
    cat > /usr/local/bin/start-mining.sh << 'EOF'
#!/bin/bash
echo "Запуск майнеров..."
/opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &
/opt/mining/kaspa/start_kaspa_miner.sh > /var/log/kaspa-miner.log 2>&1 &
echo "Майнеры запущены в фоне"
echo "Логи ETC: /var/log/etc-miner.log"
echo "Логи Kaspa: /var/log/kaspa-miner.log"
EOF

    cat > /usr/local/bin/stop-mining.sh << 'EOF'
#!/bin/bash
echo "Останавливаю майнеры..."
pkill -f "lolMiner.*ETCHASH"
pkill -f kaspa-miner
sleep 3
# Принудительно убиваем если еще остались
pkill -9 -f "lolMiner.*ETCHASH" 2>/dev/null
pkill -9 -f kaspa-miner 2>/dev/null
echo "Майнеры остановлены"
EOF

    cat > /usr/local/bin/mining-status.sh << 'EOF'
#!/bin/bash
echo "=== Статус майнеров ==="
echo "ETC Miner:"
if pgrep -f "lolMiner.*ETCHASH" > /dev/null; then
    echo "✅ Запущен (PID: $(pgrep -f "lolMiner.*ETCHASH"))"
else
    echo "❌ Не запущен"
fi
echo ""
echo "Kaspa Miner:"
if pgrep -f "kaspa-miner" > /dev/null; then
    echo "✅ Запущен (PID: $(pgrep -f kaspa-miner))"
else
    echo "❌ Не запущен"
fi
echo ""
echo "=== ЛОГИ ETC (последние 5 строк) ==="
tail -5 /var/log/etc-miner.log 2>/dev/null || echo "Файл лога не найден"
echo ""
echo "=== ЛОГИ KASPA (последние 5 строк) ==="
tail -5 /var/log/kaspa-miner.log 2>/dev/null || echo "Файл лога не найден"
EOF

    chmod +x /usr/local/bin/start-mining.sh
    chmod +x /usr/local/bin/stop-mining.sh
    chmod +x /usr/local/bin/mining-status.sh
}

# Запуск майнеров
start_miners() {
    echo "🚀 Запускаю майнеры..."
    
    # Останавливаем предыдущие instances
    /usr/local/bin/stop-mining.sh > /dev/null 2>&1
    sleep 2
    
    # Запускаем майнеры
    /usr/local/bin/start-mining.sh
    
    echo "⏳ Ожидаю запуск (10 секунд)..."
    sleep 10
}

# Проверка работы
verify_installation() {
    echo ""
    echo "=== ПРОВЕРКА УСТАНОВКИ ==="
    /usr/local/bin/mining-status.sh
    
    # Проверяем наличие бинарников
    echo ""
    echo "=== ПРОВЕРКА ФАЙЛОВ ==="
    if [ -f "/opt/mining/etc/lolMiner" ]; then
        echo "✅ ETC miner: найден ($(ls -la /opt/mining/etc/lolMiner | cut -d' ' -f5) bytes)"
    else
        echo "❌ ETC miner: НЕ НАЙДЕН"
    fi
    
    if [ -f "/opt/mining/kaspa/kaspa-miner" ]; then
        echo "✅ Kaspa miner: найден ($(ls -la /opt/mining/kaspa/kaspa-miner | cut -d' ' -f5) bytes)"
    else
        echo "❌ Kaspa miner: НЕ НАЙДЕН"
    fi
}

# Главная функция
main() {
    check_root
    install_dependencies
    main_install
    setup_autostart
    create_management_tools
    start_miners
    verify_installation
    
    echo ""
    echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
    echo "📋 Команды управления:"
    echo "   start-mining.sh    - запустить майнеры"
    echo "   stop-mining.sh     - остановить майнеры" 
    echo "   mining-status.sh   - проверить статус"
    echo ""
    echo "💡 Майнеры настроены на автозапуск при загрузке системы"
    echo "🔍 Логи: /var/log/etc-miner.log и /var/log/kaspa-miner.log"
}

# Запуск главной функции
main
