#!/bin/sh
set -u

#################################################
# STABLE MINER WITH GUARANTEED TELEGRAM REPORTS
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOST="$(hostname)"
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"
TGLOG="$LOG/telegram.log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG"

### Kryptex
KRIPTEX_USER="krxX3PVQVR"
ETC_WORKER="$KRIPTEX_USER.$HOST"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

### Telegram
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

# -------- wait for network --------
sleep 20

tg() {
  TEXT="$1"
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$TEXT" >>"$TGLOG" 2>&1 || true
}

#################################################
# INSTALLERS
#################################################

tg "🚀 [$HOST] Начало установки майнинга"

install_xmrig() {
  if [ ! -x "$BIN/cpu/xmrig" ]; then
    tg "📦 [$HOST] Установка XMRig 6.25.0"
    wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz || return
    tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1
    chmod +x "$BIN/cpu/xmrig"
    tg "✅ [$HOST] XMRig установлен"
  fi
}

install_lolminer() {
  if [ ! -x "$BIN/gpu/lolMiner" ]; then
    tg "📦 [$HOST] Установка lolMiner 1.98a"
    wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz || return
    tar -xzf /tmp/lol.tgz -C "$BIN/gpu" --strip-components=1
    chmod +x "$BIN/gpu/lolMiner"
    tg "✅ [$HOST] lolMiner установлен"
  fi
}

#################################################
# CPU — XMR
#################################################

start_cpu() {
  pkill xmrig 2>/dev/null || true
  "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX_USER.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
}

#################################################
# GPU — ETC
#################################################

start_gpu() {
  pkill lolMiner 2>/dev/null || true
  "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$ETC_WORKER" \
    --pass x \
    --ethstratum ETCPROXY \
    --disable-dag-verify \
    --apihost 127.0.0.1 --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
}

#################################################
# AUTOSTART
#################################################

crontab -l 2>/dev/null | grep -q min1.sh || \
  (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min1.sh") | crontab -

#################################################
# MAIN
#################################################

install_xmrig
install_lolminer

start_cpu
start_gpu

tg "🔥 [$HOST] Майнинг запущен
CPU: XMR
GPU: ETC (Kryptex)"

#################################################
# WATCHDOG
#################################################

while true; do
  [ -f "$RUN/cpu.pid" ] || { start_cpu; tg "♻️ [$HOST] CPU рестарт"; }
  [ -f "$RUN/gpu.pid" ] || { start_gpu; tg "♻️ [$HOST] GPU рестарт"; }
  sleep 30
done
