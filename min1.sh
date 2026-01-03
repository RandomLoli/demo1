#!/bin/bash

# ===== ENV =====
export ALLOW_MINING="${ALLOW_MINING:-0}"
[ "$ALLOW_MINING" = "1" ] || exit 0

HOST="$(hostname)"

# ===== TELEGRAM =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

tg() {
  curl -s --connect-timeout 10 \
    -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$1" >/dev/null
}

# ===== WAIT NETWORK =====
sleep 15

tg "🚀 [$HOST] Старт установки майнинга"

# ===== PATHS =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
CPU="$BIN/cpu"
GPU="$BIN/gpu"

mkdir -p "$CPU" "$GPU"

# =====================================================
# XMRIG — ВСЕГДА ПЕРЕУСТАНАВЛИВАЕМ
# =====================================================
tg "📦 [$HOST] Переустановка XMRig"

pkill xmrig >/dev/null 2>&1 || true
rm -f "$CPU/xmrig"

wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz && \
tar -xzf /tmp/xmr.tgz -C "$CPU" --strip-components=1 && \
chmod +x "$CPU/xmrig"

tg "✅ [$HOST] XMRig установлен"

# =====================================================
# LOLMINER — ВСЕГДА ПЕРЕУСТАНАВЛИВАЕМ
# =====================================================
tg "📦 [$HOST] Переустановка lolMiner"

pkill lolMiner >/dev/null 2>&1 || true
rm -f "$GPU/lolMiner"

wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz && \
tar -xzf /tmp/lol.tgz -C "$GPU" --strip-components=1 && \
chmod +x "$GPU/lolMiner"

tg "✅ [$HOST] lolMiner установлен"

# =====================================================
# ЗАПУСК XMR (CPU)
# =====================================================
"$CPU/xmrig" \
  -o xmr.kryptex.network:7029 \
  -u krxX3PVQVR.$HOST -p x \
  >/dev/null 2>&1 &

tg "⚙️ [$HOST] XMR майнер запущен"

# =====================================================
# ЗАПУСК ETC (GPU)
# =====================================================
"$GPU/lolMiner" \
  --algo ETCHASH \
  --pool etc.kryptex.network:7033 \
  --user krxX3PVQVR.worker \
  --pass x \
  --ethstratum ETCPROXY \
  >/dev/null 2>&1 &

tg "🔥 [$HOST] GPU ETC майнер запущен"
tg "✅ [$HOST] Майнинг полностью активен"

# ===== KEEP ALIVE =====
while true; do
  sleep 300
done
