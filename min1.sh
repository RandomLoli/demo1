#!/bin/bash
###############################################################################
# UNIVERSAL MINING AGENT — PRODUCTION GRADE
# CPU: XMR (XMRig)
# GPU: ETC (lolMiner, Kryptex)
# Control/Telemetry: Telegram
###############################################################################

set -o pipefail

############################
# CONFIG
############################
ALLOW_MINING="${ALLOW_MINING:-0}"
[ "$ALLOW_MINING" = "1" ] || exit 0

HOST="$(hostname)"
BASE="$HOME/.mining"
BIN_CPU="$BASE/bin/cpu"
BIN_GPU="$BASE/bin/gpu"
RUN="$BASE/run"
LOG="$BASE/log"

KRIPTEX_USER="krxX3PVQVR"
ETC_WORKER="krxX3PVQVR.worker"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

XMRIG_URL="https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz"
LOLMINER_URL="https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"

CHECK_INTERVAL=30
HASHRATE_MIN_GPU=1   # MH/s минимально допустимо

############################
# PREPARE
############################
mkdir -p "$BIN_CPU" "$BIN_GPU" "$RUN" "$LOG"

############################
# TELEGRAM
############################
tg() {
  local msg="$1"
  for _ in 1 2 3 4 5; do
    curl -fsS --connect-timeout 10 \
      -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
      -d chat_id="$TG_CHAT" \
      --data-urlencode text="$msg" >/dev/null && return 0
    sleep 5
  done
  return 1
}

############################
# NETWORK WAIT
############################
for _ in {1..20}; do
  curl -fsS https://api.telegram.org >/dev/null 2>&1 && break
  sleep 5
done

tg "🚀 [$HOST] Агент запускается (инициализация)"

############################
# CLEAN OLD STATE
############################
pkill xmrig 2>/dev/null || true
pkill lolMiner 2>/dev/null || true
rm -rf "$BIN_CPU"/* "$BIN_GPU"/*
tg "♻️ [$HOST] Старые процессы и бинарники очищены"

############################
# INSTALL XMRIG
############################
tg "📦 [$HOST] Установка XMRig (CPU → XMR)"
if wget -q "$XMRIG_URL" -O /tmp/xmrig.tgz \
  && tar -xzf /tmp/xmrig.tgz -C "$BIN_CPU" --strip-components=1 \
  && chmod +x "$BIN_CPU/xmrig"; then
  tg "✅ [$HOST] XMRig установлен"
else
  tg "❌ [$HOST] Ошибка установки XMRig"
fi

############################
# INSTALL LOLMINER
############################
tg "📦 [$HOST] Установка lolMiner (GPU → ETC)"
if wget -q "$LOLMINER_URL" -O /tmp/lolminer.tgz \
  && tar -xzf /tmp/lolminer.tgz -C "$BIN_GPU" --strip-components=1 \
  && chmod +x "$BIN_GPU/lolMiner"; then
  tg "✅ [$HOST] lolMiner установлен"
else
  tg "❌ [$HOST] Ошибка установки lolMiner"
fi

############################
# START CPU
############################
"$BIN_CPU/xmrig" \
  -o "$XMR_POOL" \
  -u "$KRIPTEX_USER.$HOST" -p x \
  --http-enabled --http-host 127.0.0.1 --http-port 16000 \
  >>"$LOG/cpu.log" 2>&1 &
echo $! > "$RUN/xmrig.pid"

sleep 3
if pgrep -f xmrig >/dev/null; then
  tg "⚙️ [$HOST] CPU → XMR запущен"
else
  tg "❌ [$HOST] CPU майнер не запустился"
fi

############################
# START GPU
############################
"$BIN_GPU/lolMiner" \
  --algo ETCHASH \
  --pool "$ETC_POOL" \
  --user "$ETC_WORKER" \
  --pass x \
  --ethstratum ETCPROXY \
  --apihost 127.0.0.1 --apiport 8080 \
  >>"$LOG/gpu.log" 2>&1 &
echo $! > "$RUN/lolminer.pid"

sleep 5
if pgrep -f lolMiner >/dev/null; then
  tg "🔥 [$HOST] GPU → ETC запущен"
else
  tg "❌ [$HOST] GPU майнер не запустился"
fi

tg "✅ [$HOST] Майнинг активен (CPU + GPU)"

############################
# WATCHDOG LOOP
############################
while true; do
  # CPU
  if ! pgrep -f xmrig >/dev/null; then
    tg "⚠️ [$HOST] XMR процесс упал → рестарт"
    "$BIN_CPU/xmrig" -o "$XMR_POOL" -u "$KRIPTEX_USER.$HOST" -p x \
      >>"$LOG/cpu.log" 2>&1 &
  fi

  # GPU
  if ! pgrep -f lolMiner >/dev/null; then
    tg "⚠️ [$HOST] ETC процесс упал → рестарт"
    "$BIN_GPU/lolMiner" --algo ETCHASH --pool "$ETC_POOL" \
      --user "$ETC_WORKER" --pass x --ethstratum ETCPROXY \
      >>"$LOG/gpu.log" 2>&1 &
  fi

  # Hashrate check (GPU)
  HR=$(curl -s http://127.0.0.1:8080/summary \
    | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  HR="${HR:-0}"

  if (( $(echo "$HR < $HASHRATE_MIN_GPU" | bc -l) )); then
    tg "⚠️ [$HOST] GPU хешрейт низкий (${HR} MH/s) → рестарт"
    pkill lolMiner && sleep 2
  fi

  sleep "$CHECK_INTERVAL"
done
