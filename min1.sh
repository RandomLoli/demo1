#!/bin/bash

# ===== STRICT BUT SAFE =====
set -o pipefail

# ===== ENV =====
export ALLOW_MINING="${ALLOW_MINING:-0}"
[ "$ALLOW_MINING" = "1" ] || exit 0

HOST="$(hostname)"

# ===== TELEGRAM =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

tg() {
  local msg="$1"
  # 5 попыток с паузами
  for i in 1 2 3 4 5; do
    curl -fsS --connect-timeout 10 \
      -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
      -d chat_id="$TG_CHAT" \
      --data-urlencode text="$msg" && return 0
    sleep 5
  done
  return 1
}

# ===== WAIT NETWORK (HARD) =====
for i in {1..12}; do
  curl -fsS https://api.telegram.org >/dev/null 2>&1 && break
  sleep 5
done

tg "🚀 [$HOST] Старт установки майнинга"

# ===== PATHS =====
BASE="$HOME/.mining"
CPU="$BASE/bin/cpu"
GPU="$BASE/bin/gpu"
mkdir -p "$CPU" "$GPU"

# =====================================================
# XMRIG — ВСЕГДА ПЕРЕУСТАНОВКА
# =====================================================
tg "📦 [$HOST] Переустановка XMRig (CPU → XMR)"

pkill xmrig >/dev/null 2>&1 || true
rm -f "$CPU/xmrig"

if wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz \
  && tar -xzf /tmp/xmr.tgz -C "$CPU" --strip-components=1 \
  && chmod +x "$CPU/xmrig"; then
  tg "✅ [$HOST] XMRig установлен"
else
  tg "❌ [$HOST] Ошибка установки XMRig"
fi

# =====================================================
# LOLMINER — ВСЕГДА ПЕРЕУСТАНОВКА
# =====================================================
tg "📦 [$HOST] Переустановка lolMiner (GPU → ETC)"

pkill lolMiner >/dev/null 2>&1 || true
rm -f "$GPU/lolMiner"

if wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz \
  && tar -xzf /tmp/lol.tgz -C "$GPU" --strip-components=1 \
  && chmod +x "$GPU/lolMiner"; then
  tg "✅ [$HOST] lolMiner установлен"
else
  tg "❌ [$HOST] Ошибка установки lolMiner"
fi

# =====================================================
# ЗАПУСК CPU (XMR)
# =====================================================
"$CPU/xmrig" \
  -o xmr.kryptex.network:7029 \
  -u krxX3PVQVR.$HOST -p x \
  >/dev/null 2>&1 &

sleep 5
if pgrep -f "$CPU/xmrig" >/dev/null; then
  tg "⚙️ [$HOST] XMR (CPU) запущен"
else
  tg "❌ [$HOST] XMR (CPU) НЕ ЗАПУСТИЛСЯ"
fi

# =====================================================
# ЗАПУСК GPU (ETC)
# =====================================================
"$GPU/lolMiner" \
  --algo ETCHASH \
  --pool etc.kryptex.network:7033 \
  --user krxX3PVQVR.worker \
  --pass x \
  --ethstratum ETCPROXY \
  >/dev/null 2>&1 &

sleep 5
if pgrep -f "$GPU/lolMiner" >/dev/null; then
  tg "🔥 [$HOST] ETC (GPU) запущен"
else
  tg "❌ [$HOST] ETC (GPU) НЕ ЗАПУСТИЛСЯ"
fi

tg "✅ [$HOST] Установка завершена, майнинг активен"

# ===== KEEP ALIVE (простая защита) =====
while true; do
  sleep 300
  pgrep -f "$CPU/xmrig" >/dev/null || tg "⚠️ [$HOST] XMR процесс пропал"
  pgrep -f "$GPU/lolMiner" >/dev/null || tg "⚠️ [$HOST] ETC процесс пропал"
done
