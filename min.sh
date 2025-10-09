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
    
    # Убедимся, что cron установлен
    if ! command -v crontab &> /dev/null; then
        echo "📥 Устанавливаю cron..."
        apt-get update && apt-get install -y cron
    fi
}

# Установка и настройка lolMiner для ETC
install_etc_miner() {
    echo "📥 Устанавливаю lolMiner для ETC..."
    mkdir -p /opt/mining/etc
    cd /opt/mining/etc

    if ! wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz; then
        echo "❌ Ошибка загрузки lolMiner"
        return 1
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

    if ! wget -q https://github.com/doktor83/SRBMiner-Multi/releases/download/2.9.8/SRBMiner-Multi-2-9-8-Linux.tar.gz -O srbminer.tar.gz; then
        echo "❌ Ошибка загрузки SRBMiner"
        return 1
    fi

    # Распаковываем архив
    echo "📦 Распаковываю SRBMiner..."
    tar -xzf srbminer.tar.gz --strip-components=1
    rm -f srbminer.tar.gz

    # Проверяем наличие бинарника
    if [ ! -f "SRBMiner-MULTI" ]; then
        echo "❌ Бинарник SRBMiner-MULTI не найден после распаковки"
        return 1
    fi

    chmod +x SRBMiner-MULTI

    # Создаем скрипт запуска для Kaspa
    cat > /opt/mining/kaspa/start_kaspa_miner.sh << EOF
#!/bin/bash
cd /opt/mining/kaspa
./SRBMiner-MULTI --algorithm kheavyhash --pool $KASPA_POOL --wallet $KASPA_WALLET --worker worker --gpu-boost 3 --disable-cpu
EOF
    chmod +x /opt/mining/kaspa/start_kaspa_miner.sh
    echo "✅ SRBMiner-MULTI для Kaspa установлен и настроен"
}

# Настройка автозапуска через cron
setup_autostart() {
    echo "⏰ Настраиваю автозапуск через cron..."
    
    # Добавляем задания в crontab для автозапуска при загрузке
    (crontab -l 2>/dev/null | grep -v "/opt/mining/etc/start_etc_miner.sh"; echo "@reboot /opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &") | crontab -
    (crontab -l 2>/dev/null | grep -v "/opt/mining/kaspa/start_kaspa_miner.sh"; echo "@reboot /opt/mining/kaspa/start_kaspa_miner.sh > /var/log/kaspa-miner.log 2>&1 &") | crontab -
    
    echo "✅ Автозапуск через cron настроен"
}

# Создание утилит управления без systemd
create_management_tools() {
    echo "🔧 Создаю утилиты управления..."

    # Создаем PID файлы для отслеживания процессов
    mkdir -p /var/run/mining

    cat > /usr/local/bin/start-mining.sh << 'EOF'
#!/bin/bash
echo "Запуск майнеров..."

# Проверяем, не запущены ли уже майнеры
if [ -f "/var/run/mining/etc.pid" ]; then
    echo "⚠️  ETC майнер уже запущен (PID: $(cat /var/run/mining/etc.pid))"
else
    /opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &
    echo $! > /var/run/mining/etc.pid
    echo "✅ ETC майнер запущен (PID: $!)"
fi

if [ -f "/var/run/mining/kaspa.pid" ]; then
    echo "⚠️  Kaspa майнер уже запущен (PID: $(cat /var/run/mining/kaspa.pid))"
else
    /opt/mining/kaspa/start_kaspa_miner.sh > /var/log/kaspa-miner.log 2>&1 &
    echo $! > /var/run/mining/kaspa.pid
    echo "✅ Kaspa майнер запущен (PID: $!)"
fi

echo ""
echo "📊 Для проверки статуса используй: mining-status.sh"
EOF

    cat > /usr/local/bin/stop-mining.sh << 'EOF'
#!/bin/bash
echo "Останавливаю майнеры..."

# Останавливаем ETC майнер
if [ -f "/var/run/mining/etc.pid" ]; then
    etc_pid=$(cat /var/run/mining/etc.pid)
    if kill $etc_pid 2>/dev/null; then
        echo "✅ ETC майнер остановлен (PID: $etc_pid)"
    else
        echo "⚠️  ETC майнер уже не запущен"
    fi
    rm -f /var/run/mining/etc.pid
else
    echo "ℹ️  ETC майнер не был запущен через start-mining.sh"
    pkill -f "lolMiner.*ETCHASH" && echo "✅ ETC майнер остановлен (принудительно)" || echo "ℹ️  ETC майнер не найден"
fi

# Останавливаем Kaspa майнер
if [ -f "/var/run/mining/kaspa.pid" ]; then
    kaspa_pid=$(cat /var/run/mining/kaspa.pid)
    if kill $kaspa_pid 2>/dev/null; then
        echo "✅ Kaspa майнер остановлен (PID: $kaspa_pid)"
    else
        echo "⚠️  Kaspa майнер уже не запущен"
    fi
    rm -f /var/run/mining/kaspa.pid
else
    echo "ℹ️  Kaspa майнер не был запущен через start-mining.sh"
    pkill -f "SRBMiner-MULTI.*kheavyhash" && echo "✅ Kaspa майнер остановлен (принудительно)" || echo "ℹ️  Kaspa майнер не найден"
fi
EOF

    cat > /usr/local/bin/mining-status.sh << 'EOF'
#!/bin/bash
echo "=== Статус майнеров ==="

# Проверяем ETC майнер
etc_pid=""
if [ -f "/var/run/mining/etc.pid" ]; then
    etc_pid=$(cat /var/run/mining/etc.pid)
fi

if [ -n "$etc_pid" ] && kill -0 $etc_pid 2>/dev/null; then
    echo "✅ ETC Miner: Запущен (PID: $etc_pid)"
else
    echo "❌ ETC Miner: Не запущен"
    # Удаляем невалидный PID файл
    [ -f "/var/run/mining/etc.pid" ] && rm -f /var/run/mining/etc.pid
fi

# Проверяем Kaspa майнер
kaspa_pid=""
if [ -f "/var/run/mining/kaspa.pid" ]; then
    kaspa_pid=$(cat /var/run/mining/kaspa.pid)
fi

if [ -n "$kaspa_pid" ] && kill -0 $kaspa_pid 2>/dev/null; then
    echo "✅ Kaspa Miner: Запущен (PID: $kaspa_pid)"
else
    echo "❌ Kaspa Miner: Не запущен"
    # Удаляем невалидный PID файл
    [ -f "/var/run/mining/kaspa.pid" ] && rm -f /var/run/mining/kaspa.pid
fi

echo ""
echo "=== Логи ETC (последние 5 строк) ==="
if [ -f "/var/log/etc-miner.log" ]; then
    tail -5 /var/log/etc-miner.log
else
    echo "Файл лога не найден"
fi

echo ""
echo "=== Логи Kaspa (последние 5 строк) ==="
if [ -f "/var/log/kaspa-miner.log" ]; then
    tail -5 /var/log/kaspa-miner.log
else
    echo "Файл лога не найден"
fi

echo ""
echo "=== Активные процессы ==="
pgrep -f "lolMiner.*ETCHASH" > /dev/null && echo "ETC процесс: $(pgrep -f 'lolMiner.*ETCHASH')" || echo "ETC процесс: не найден"
pgrep -f "SRBMiner-MULTI.*kheavyhash" > /dev/null && echo "Kaspa процесс: $(pgrep -f 'SRBMiner-MULTI.*kheavyhash')" || echo "Kaspa процесс: не найден"
EOF

    chmod +x /usr/local/bin/start-mining.sh
    chmod +x /usr/local/bin/stop-mining.sh
    chmod +x /usr/local/bin/mining-status.sh

    echo "✅ Утилиты управления созданы"
}

# Запуск майнеров
start_miners() {
    echo "🚀 Запускаю майнеры..."
    /usr/local/bin/start-mining.sh
    echo "⏳ Ожидаю запуск (10 секунд)..."
    sleep 10
}

# Проверка установки
verify_installation() {
    echo ""
    echo "=== ПРОВЕРКА УСТАНОВКИ ==="
    echo "Файлы:"
    if [ -f "/opt/mining/etc/lolMiner" ]; then
        echo "✅ ETC miner: найден ($(ls -la /opt/mining/etc/lolMiner | cut -d' ' -f5) bytes)"
    else
        echo "❌ ETC miner: НЕ НАЙДЕН"
    fi
    
    if [ -f "/opt/mining/kaspa/SRBMiner-MULTI" ]; then
        echo "✅ Kaspa miner: найден ($(ls -la /opt/mining/kaspa/SRBMiner-MULTI | cut -d' ' -f5) bytes)"
    else
        echo "❌ Kaspa miner: НЕ НАЙДЕН"
    fi
    
    echo ""
    echo "Статус:"
    /usr/local/bin/mining-status.sh
}

# Главная функция
main() {
    check_root
    install_dependencies
    
    if ! install_etc_miner; then
        echo "❌ Ошибка установки ETC майнера"
        exit 1
    fi
    
    if ! install_kaspa_miner; then
        echo "❌ Ошибка установки Kaspa майнера"
        echo "⚠️  Продолжаю настройку без Kaspa майнера"
    fi
    
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
    echo "💡 Майнеры настроены на автозапуск при загрузке системы через cron"
    echo "📝 Логи пишутся в: /var/log/etc-miner.log и /var/log/kaspa-miner.log"
}

# Запуск
main
