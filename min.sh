#!/bin/bash
set -e

# === КОНФИГУРАЦИЯ ===
POOL_ETC="stratum+tcp://gate.emcd.network:7878"
POOL_KAS="stratum+tcp://gate.emcd.network:9999"
WALLET="grammymurr.worker"

# 🔑 Замените на ваши данные!
TELEGRAM_BOT_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TELEGRAM_CHAT_ID="5336452267"

HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')

send_telegram() {
    local msg="$1"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d "chat_id=$TELEGRAM_CHAT_ID" \
        -d "text=$msg" \
        -d "parse_mode=HTML" > /dev/null
}

echo "🚀 Начинаю развёртывание майнинга на $HOSTNAME ($IP)"
send_telegram "⛏️ <b>Запуск майнинга</b> на $HOSTNAME ($IP)..."

# === 1. KASPA (CPU, через универсальную Linux-сборку) ===
KAS_DIR="$HOME/kaspa-miner"
mkdir -p "$KAS_DIR"
cd "$KAS_DIR"

echo "📦 Скачиваю Kaspa-майнер (Linux)..."
wget -q https://github.com/tmrlvi/kaspa-miner/releases/download/v0.2.1-GPU-0.7/kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
tar -xf kaspa-miner-v0.2.1-GPU-0.7-default-linux-gnu-amd64.tgz
mv kaspa-miner ./
chmod +x kaspa-miner

# Проверяем, что бинарник запускается
./kaspa-miner --help > /dev/null || { echo "❌ Ошибка: бинарник несовместим"; exit 1; }

cat > start.sh <<EOF
#!/bin/bash
cd "$KAS_DIR"
./kaspa-miner --pool $POOL_KAS --user $WALLET --threads \$(nproc)
EOF
chmod +x start.sh

# Systemd сервис
cat > /tmp/kaspa-miner.service <<EOF
[Unit]
Description=Kaspa Miner (CPU)
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$KAS_DIR
ExecStart=$KAS_DIR/start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/kaspa-miner.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kaspa-miner
sudo systemctl restart kaspa-miner

KAS_OK="✅ Kaspa — запущен (CPU)"

# === 2. ETC (GPU, через lolMiner v1.98) ===
GPU_FOUND=false
if command -v nvidia-smi >/dev/null 2>&1 || (lspci | grep -iE 'vga|amd|ati' > /dev/null); then
    GPU_FOUND=true
fi

ETC_OK=""
if [ "$GPU_FOUND" = true ]; then
    ETC_DIR="$HOME/etc-miner"
    mkdir -p "$ETC_DIR"
    cd "$ETC_DIR"

    echo "🎮 GPU обнаружен — устанавливаю lolMiner 1.98..."
    wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz
    tar -xf lolMiner_v1.98_Lin64.tar.gz
    mv 1.98/lolMiner ./
    chmod +x lolMiner

    cat > start.sh <<EOF
#!/bin/bash
cd "$ETC_DIR"
./lolMiner --algo ETCHASH --pool $POOL_ETC --user $WALLET --apiport 4444
EOF
    chmod +x start.sh

    cat > /tmp/etc-miner.service <<EOF
[Unit]
Description=ETC Miner (GPU)
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$ETC_DIR
ExecStart=$ETC_DIR/start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/etc-miner.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable etc-miner
    sudo systemctl restart etc-miner

    ETC_OK="✅ ETC — запущен (GPU)"
else
    ETC_OK="⚠️ GPU не найден — ETC пропущен"
fi

# === Уведомление в Telegram ===
send_telegram "✅ <b>Майнинг активен</b> на $HOSTNAME ($IP)

$KAS_OK
$ETC_OK

🕒 $(date '+%Y-%m-%d %H:%M:%S')"
echo "✅ Готово! Проверьте Telegram."
