#!/bin/sh
set -u

############################################
# ULTRA HARDENED MINING AGENT (SAFE MODE)
# Requires explicit opt-in: ALLOW_MINING=1
############################################

[ "${ALLOW_MINING:-0}" = "1" ] || {
  echo "Mining disabled. Set ALLOW_MINING=1 to proceed."
  exit 0
}

### ===== PANEL =====
PANEL="http://178.47.141.130:3333"
TOKEN="mamont22187"
INTERVAL=30

### ===== XMRIG =====
POOL="xmr.kryptex.network:7029"
USER="krxX3PVQVR.$(hostname)"

### ===== PATHS (NON-ROOT SAFE) =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/xmr" "$RUN" "$LOG" >/dev/null 2>&1 || true

############################################
# -------- UTILS ---------------------------
############################################

log() { echo "$(date '+%F %T') $*" >> "$LOG/agent.log"; }

retry() {
  n=0
  until [ $n -ge 5 ]; do
    "$@" && return 0
    n=$((n+1))
    sleep $((n*2))
  done
  return 1
}

############################################
# -------- PANEL API -----------------------
############################################

send_event() {
  retry curl -s "$PANEL/api/event" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$(hostname)\",
      \"level\": \"$1\",
      \"message\": \"$2\"
    }" >/dev/null 2>&1 || true
}

send_telemetry() {
  HASHRATE="$(get_hashrate)"
  STATUS="stopped"
  [ -f "$RUN/xmrig.pid" ] && STATUS="running"

  retry curl -s "$PANEL/api/telemetry" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$(hostname)\",
      \"cpu_mining\": \"$STATUS\",
      \"gpu_mining\": \"stopped\",
      \"gpu_detected\": false,
      \"hashrate\": $HASHRATE
    }" >/dev/null 2>&1 || true
}

############################################
# -------- XMRIG API -----------------------
############################################

get_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+(\.[0-9]+)?' \
    | head -1 || echo 0
}

############################################
# -------- XMRIG CONTROL -------------------
############################################

start_xmrig() {
  stop_xmrig
  nohup "$BIN/xmr/xmrig" \
    -o "$POOL" -u "$USER" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/xmrig.log" 2>&1 &
  echo $! > "$RUN/xmrig.pid"
  log "xmrig started"
}

stop_xmrig() {
  [ -f "$RUN/xmrig.pid" ] && kill "$(cat "$RUN/xmrig.pid")" 2>/dev/null || true
  rm -f "$RUN/xmrig.pid"
}

############################################
# -------- INSTALL -------------------------
############################################

install_xmrig() {
  [ -x "$BIN/xmr/xmrig" ] && return
  retry wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz || return
  tar -xzf /tmp/xmr.tgz -C "$BIN/xmr" --strip-components=1
  chmod +x "$BIN/xmr/xmrig"
}

############################################
# -------- AUTOSTART (SAFE) ----------------
############################################

ensure_autostart() {
  (crontab -l 2>/dev/null | grep -q "ALLOW_MINING=1 $BASE/agent.sh") && return
  (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/agent.sh") | crontab -
}

############################################
# -------- AGENT LOOP ----------------------
############################################

agent_loop() {
  send_event "INFO" "Ultra agent started"
  ensure_autostart
  start_xmrig

  ZERO=0
  while true; do
    HR="$(get_hashrate)"
    send_telemetry

    if [ "$HR" = "0" ]; then
      ZERO=$((ZERO+1))
      [ "$ZERO" -ge 3 ] && {
        send_event "WARNING" "Hashrate 0 — restarting xmrig"
        start_xmrig
        ZERO=0
      }
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
agent_loop
