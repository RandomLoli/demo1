#!/bin/sh
set -eu

#################################################
# STABLE MINER
# CPU: XMR (XMRig, Kryptex)
# GPU: ETC (lolMiner, Kryptex)
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOST="$(hostname)"
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG"

# ===== Kryptex =====
KRIPTEX_USER="krxX3PVQVR"
ETC_WORKER="krxX3PVQVR.worker"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# ===== Telegram =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

tg() {
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$1" >/dev/null 2>&1
}

#################################################
# INSTALLERS
#################################################

install_xmrig() {
  [ -x "$BIN/cpu/xmrig" ] && return
  tg "⚙️ [$HOST] Installing XMRig 6.25.0"
  wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1
  chmod +x "$BIN/cpu/xmrig"
}

install_lolminer() {
  [ -x "$BIN/gpu/lolMiner" ] && return
  tg "⚙️ [$HOST] Installing lolMiner 1.98a"
  wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz
  tar -xzf /tmp/lol.tgz -C "$BIN/gpu" --strip-components=1
  chmod +x "$BIN/gpu/lolMiner"
}

#################################################
# CPU — XMR
#################################################

start_cpu() {
  pkill xmrig 2>/dev/null || true
  nohup "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX_USER.$HOST" -p x \
    --http-enabled \
    --http-host 127.0.0.1 \
    --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
}

cpu_hr() {
  curl -s http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+' | head -1 || echo 0
}

#################################################
# GPU — ETC
#################################################

start_gpu() {
  pkill lolMiner 2>/dev/null || true
  nohup "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$ETC_WORKER" \
    --pass x \
    --ethstratum ETCPROXY \
    --disable-dag-verify \
    --watchdog exit \
    --apihost 127.0.0.1 \
    --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
}

gpu_hr() {
  curl -s http://127.0.0.1:8080/summary \
    | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?' || echo 0
}

#################################################
# AUTOSTART
#################################################

enable_autostart() {
  crontab -l 2>/dev/null | grep -q min1.sh || \
    (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min1.sh") | crontab -
}

#################################################
# WATCHDOG
#################################################

watchdog() {

  [ -f "$RUN/cpu.pid" ] || { start_cpu; tg "♻️ [$HOST] CPU restarted"; }
  [ -f "$RUN/gpu.pid" ] || { start_gpu; tg "♻️ [$HOST] GPU restarted"; }

  GPU="$(gpu_hr)"

  if [ "$(printf "%.0f" "$GPU")" -eq 0 ]; then
    start_gpu
    tg "⚠️ [$HOST] ETC hashrate = 0 → GPU restart"
  fi
}

#################################################
# MAIN
#################################################

tg "🚀 [$HOST] Mining start"
install_xmrig
install_lolminer
enable_autostart
start_cpu
start_gpu
tg "✅ [$HOST] Mining running"

while true; do
  watchdog
  sleep 30
done
