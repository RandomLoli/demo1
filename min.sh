#!/bin/sh
set -e

# === КОНФИГУРАЦИЯ ===
POOL_ETC="stratum+tcp://gate.emcd.network:7878"
POOL_KAS="stratum+tcp://gate.emcd.network:9999"
WALLET="grammymurr.worker"

# Работаем в папке скрипта
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
echo "🚀 Запуск майнинга на $HOSTNAME ($IP)"

# === ФУНКЦИЯ: установка systemd-сервиса ===
setup_service() {
    NAME="$1"
    START_CMD="$2"
    cat > "/tmp/${NAME}.service" <<EOF
[Unit]
Description=$NAME Miner
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$START_CMD
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    sudo mv "/tmp/${NAME}.service" "/etc/systemd/system/"
    sudo systemctl daemon-reload
    sudo systemctl enable "$NAME.service"
    sudo systemctl restart "$NAME.service"
}

# === 1. KASPA (CPU) ===
echo "📦 Устанавливаю Kaspa (CPU)..."
if [ ! -f kaspa-miner ]; then
    wget -q -L -O kaspa.tgz "https://github.com/tmrlvi/kaspa-miner/releases/download/v0.2.1-GPU-0.7/kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz"
    [ -s kaspa.tgz ] || { echo "❌ Kaspa: архив не скачался"; exit 1; }
    tar -xf kaspa.tgz
    KAS_BIN=$(find . -type f -name "kaspa-miner" | head -n1)
    [ -n "$KAS_BIN" ] || { echo "❌ Kaspa: бинарник не найден"; exit 1; }
    cp "$KAS_BIN" ./kaspa-miner
    chmod +x kaspa-miner
fi

setup_service "kaspa-miner" "./kaspa-miner --pool $POOL_KAS --user $WALLET --threads \$(nproc)"

# === 2. ETC (GPU) ===
GPU_FOUND=false
if command -v nvidia-smi >/dev/null 2>&1 || (lspci | grep -iE 'vga|3d|amd|ati' >/dev/null); then
    GPU_FOUND=true
fi

if [ "$GPU_FOUND" = true ]; then
    echo "🎮 Устанавливаю ETC (GPU)..."
    if [ ! -f lolMiner ]; then
        wget -q -O lolMiner.tar.gz "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz"
        [ -s lolMiner.tar.gz ] || { echo "❌ ETC: архив не скачался"; exit 1; }
        tar -xf lolMiner.tar.gz
        mv 1.98/lolMiner ./
        chmod +x lolMiner
    fi
    setup_service "etc-miner" "./lolMiner --algo ETCHASH --pool $POOL_ETC --user $WALLET --apiport 4444"
else
    echo "⚠️ GPU не найден — ETC пропущен"
fi

echo "✅ Майнинг настроен! Сервисы:"
echo "   sudo systemctl status kaspa-miner"
[ "$GPU_FOUND" = true ] && echo "   sudo systemctl status etc-miner"
echo "   Логи: journalctl -u kaspa-miner -f"
