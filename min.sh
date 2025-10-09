#!/bin/sh
set -e

# === КОНФИГУРАЦИЯ ===
POOL_HOST="gate.emcd.network"
WALLET="grammymurr.worker"

# Работаем в папке скрипта
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Запуск майнинга в $SCRIPT_DIR"

# =============== KASPA (CPU) ===============
if [ ! -f kaspaminer ]; then
    echo "📦 Устанавливаю Kaspa (CPU)..."
    # Используем HIVEOS-архив — в нём есть бинарник!
    wget -q -L -O kaspa.tgz "https://github.com/tmrlvi/kaspa-miner/releases/download/v0.2.1-GPU-0.7/kaspa-miner-hiveos.tgz"
    [ -s kaspa.tgz ] || { echo "❌ Kaspa: архив не скачался"; exit 1; }
    tar -xf kaspa.tgz
    # Бинарник лежит прямо в корне архива
    if [ ! -f kaspaminer ]; then
        echo "❌ kaspaminer не найден после распаковки"
        ls -la
        exit 1
    fi
    chmod +x kaspaminer
fi

cat > /tmp/kaspa-miner.service <<EOF
[Unit]
Description=Kaspa Miner
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/kaspaminer --mining-address $WALLET --kaspad-address $POOL_HOST --port 9999 --threads \$(nproc)
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/kaspa-miner.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kaspa-miner
sudo systemctl restart kaspa-miner
echo "✅ Kaspa — запущен"

# =============== ETC (GPU) ===============
GPU_FOUND=false
if command -v nvidia-smi >/dev/null 2>&1 || (lspci | grep -iE 'vga|3d|amd|ati' >/dev/null); then
    GPU_FOUND=true
fi

if [ "$GPU_FOUND" = true ]; then
    if [ ! -f lolMiner ]; then
        echo "🎮 Устанавливаю ETC (GPU)..."
        wget -q -O lolMiner.tar.gz "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz"
        tar -xf lolMiner.tar.gz
        mv 1.98/lolMiner ./
        chmod +x lolMiner
    fi

    cat > /tmp/etc-miner.service <<EOF
[Unit]
Description=ETC Miner
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/lolMiner --algo ETCHASH --pool stratum+tcp://$POOL_HOST:7878 --user $WALLET --tls off --nocolor
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/etc-miner.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable etc-miner
    sudo systemctl restart etc-miner
    echo "✅ ETC — запущен"
else
    echo "⚠️ GPU не найден — ETC пропущен"
fi

echo "✅ Готово! Статус:"
echo "   Kaspa: sudo systemctl status kaspa-miner"
[ "$GPU_FOUND" = true ] && echo "   ETC:   sudo systemctl status etc-miner"
