#!/bin/bash

# Конфигурация для Kryptex (замените на свои данные!)
KRIPTEX_USERNAME="krxX3PVQVR"  # Ваш имейл или имя пользователя на Kryptex
WORKER_NAME="worker"            # Имя воркера, которое вы увидите в статистике

# Пул и порты Kryptex
ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

# Формируем логины для пула
ETC_USERNAME="$KRIPTEX_USERNAME.$WORKER_NAME"
XMR_USERNAME="$KRIPTEX_USERNAME.$WORKER_NAME"

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
        apt-get update && apt-get install -y wget
    fi
    if ! command -v crontab &> /dev/null; then
        apt-get update && apt-get install -y cron
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
    else
        echo "❌ Ошибка загрузки lolMiner"
        return 1
    fi
}

# Установка XMRig для Monero (CPU) - ИСПРАВЛЕННАЯ ВЕРСИЯ
install_xmr_miner() {
    echo "📥 Устанавливаю XMRig для Monero..."
    mkdir -p /opt/mining/xmr
    cd /opt/mining/xmr

    # Скачиваем и распаковываем XMRig
    if wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz; then
        tar -xzf xmrig-*-linux-x64.tar.gz --strip-components=1
        rm -f xmrig-*-linux-x64.tar.gz

        # ИСПРАВЛЕННЫЙ скрипт запуска для XMR (без --algorithm)
        cat > /opt/mining/xmr/start_xmr_miner.sh << EOF
#!/bin/bash
cd /opt/mining/xmr
./xmrig -o $XMR_POOL -u $XMR_USERNAME -p x
EOF
        chmod +x /opt/mining/xmr/start_xmr_miner.sh
        echo "✅ XMRig для Monero установлен и настроен"
    else
        echo "❌ Ошибка загрузки XMRig"
        return 1
    fi
}

setup_autostart() {
    echo "⏰ Настраиваю автозапуск через cron..."
    # Добавляем задания в crontab для автозапуска при загрузке
    (crontab -l 2>/dev/null | grep -v "/opt/mining/etc/start_etc_miner.sh"; echo "@reboot /opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &") | crontab -
    (crontab -l 2>/dev/null | grep -v "/opt/mining/xmr/start_xmr_miner.sh"; echo "@reboot /opt/mining/xmr/start_xmr_miner.sh > /var/log/xmr-miner.log 2>&1 &") | crontab -
    echo "✅ Автозапуск через cron настроен"
}

create_management_tools() {
    echo "🔧 Создаю утилиты управления..."

    cat > /usr/local/bin/start-mining.sh << 'EOF'
#!/bin/bash
echo "Запуск майнеров..."
/opt/mining/etc/start_etc_miner.sh > /var/log/etc-miner.log 2>&1 &
/opt/mining/xmr/start_xmr_miner.sh > /var/log/xmr-miner.log 2>&1 &
echo "✅ Майнеры запущены в фоне"
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

    mkdir -p /var/run/mining
    chmod +x /usr/local/bin/start-mining.sh /usr/local/bin/stop-mining.sh /usr/local/bin/mining-status.sh
    echo "✅ Утилиты управления созданы"
}

# Функция для исправления XMR майнера
fix_xmr_miner() {
    echo "🔧 Исправляю XMR майнер..."
    cd /opt/mining/xmr
    
    # Останавливаем текущий XMR майнер
    pkill -f xmrig
    sleep 2
    
    # Обновляем скрипт запуска с правильными параметрами
    cat > start_xmr_miner.sh << EOF
#!/bin/bash
cd /opt/mining/xmr
./xmrig -o $XMR_POOL -u $XMR_USERNAME -p x
EOF
    chmod +x start_xmr_miner.sh
    echo "✅ XMR майнер исправлен"
}

main() {
    check_root
    
    echo "Выберите действие:"
    echo "1 - Полная установка майнеров"
    echo "2 - Только исправить XMR майнер"
    read -p "Введите номер [1-2]: " choice
    
    case $choice in
        1)
            install_dependencies
            install_etc_miner
            install_xmr_miner
            setup_autostart
            create_management_tools
            ;;
        2)
            fix_xmr_miner
            ;;
        *)
            echo "❌ Неверный выбор"
            exit 1
            ;;
    esac

    echo "🚀 Запускаю майнеры..."
    /usr/local/bin/stop-mining.sh > /dev/null 2>&1
    sleep 3
    /usr/local/bin/start-mining.sh
    sleep 5

    echo ""
    echo "🎉 НАСТРОЙКА ЗАВЕРШЕНА!"
    echo "📊 Статус:"
    /usr/local/bin/mining-status.sh

    echo ""
    echo "📋 Команды управления:"
    echo "   start-mining.sh    - запустить майнеры"
    echo "   stop-mining.sh     - остановить майнеры"
    echo "   mining-status.sh   - проверить статус и логи"
    echo ""
    echo "💡 Майнеры настроены на автозапуск при перезагрузке"
    echo "📈 Статистика появится в личном кабинете Kryptex через 10-15 минут"
}

main
