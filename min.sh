#!/bin/sh
set -eu

####################################
# MINING CONTROL CENTER — AGENT
# FINAL v1
####################################

### ===== PANEL CONFIG =====
PANEL="http://178.47.141.130:3333"
TOKEN="mamont22187"
INTERVAL=30

### ===== MINING CONFIG =====
KRIPTEX_USERNAME="krxX3PVQVR"
HOST="$(hostname)"

ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

BASE="/opt/mining"
LOG="/var/log/mining"

ETC_USER="${KRIPTEX_USERNAME}.${HOST}"
XMR_USER="${KRIPTEX_USERNAME}.${HOST}"

####################################
have() { command -v "$1" >/dev/null 2>&1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || exit 1
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
    }" >/dev/null || true
}

send_telemetry() {
  CPU_STATUS="$(systemctl is-active mining-cpu 2>/dev/null || echo stopped)"
  GPU_STATUS="$(systemctl is-active mining-gpu 2>/dev/null || echo stopped)"

  GPU_OK=false
  lspci | grep -qiE "nvidia|amd" && GPU_OK=true

  HASHRATE=$(grep -i hashrate "$LOG/xmr.log" 2>/dev/null | tail -1 | grep -oE '[0-9]+' || echo 0)

  CPU_TEMP=$(sensors 2>/dev/null | awk '/Tctl|CPU Temp/ {print $2}' | tr -d '+°C' | head -1 || true)
  GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1 || true)

  curl -s "$PANEL/api/telemetry" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$HOST\",
      \"cpu_mining\": \"$CPU_STATUS\",
      \"gpu_mining\": \"$GPU_STATUS\",
      \"gpu_detected\": $GPU_OK,
      \"hashrate\": $HASHRATE,
      \"cpu_temp\": ${CPU_TEMP:-null},
      \"gpu_temp\": ${GPU_TEMP:-null}
    }" >/dev/null || true
}

####################################
# -------- CONTROL -----------------
####################################

ack_command() {
  curl -s "$PANEL/api/control/ack" \
    -H "Content-Type: application/json" \
    -H "token: $TOKEN" \
    -d "{
      \"hostname\": \"$HOST\",
      \"command_id\": $1,
      \"result\": \"$2\",
      \"message\": \"$3\"
    }" >/dev/null || true
}

check_control() {
  RESP=$(curl -s "$PANEL/api/control/pending?hostname=$HOST" -H "token: $TOKEN")
  echo "$RESP" | grep -q '"action"' || return

  CMD_ID=$(echo "$RESP" | grep -oE '"id":[0-9]+' | grep -oE '[0-9]+')
  ACTION=$(echo "$RESP" | grep -oE '"action":"[^"]+' | cut -d'"' -f4)

  case "$ACTION" in
    start_cpu) systemctl start mining-cpu ;;
    stop_cpu) systemctl stop mining-cpu ;;
    start_gpu) systemctl start mining-gpu ;;
    stop_gpu) systemctl stop mining-gpu ;;
    restart_all)
      systemctl restart mining-cpu
      systemctl restart mining-gpu
    ;;
    *)
      ack_command "$CMD_ID" "failed" "Unknown action"
      return
    ;;
  esac

  ack_command "$CMD_ID" "success" "$ACTION executed"
}

####################################
# -------- WATCHDOG ----------------
####################################

watchdog() {
  [ "$HASHRATE" = "0" ] && \
    send_event "CRITICAL" "XMR hashrate = 0"
}

####################################
# -------- DAY / NIGHT -------------
####################################

day_night_mode() {
  HOUR=$(date +%H)
  if [ "$HOUR" -ge 1 ] && [ "$HOUR" -le 7 ]; then
    systemctl stop mining-cpu
  else
    systemctl start mining-cpu
  fi
}

####################################
# -------- INSTALL -----------------
####################################

install_deps() {
  for pm in apt-get dnf yum pacman zypper; do
    have "$pm" && PM="$pm" && break
  done

  case "$PM" in
    apt-get) apt-get update && apt-get install -y curl wget tar lm-sensors pciutils ;;
    dnf|yum) $PM install -y curl wget tar lm_sensors pciutils ;;
    pacman) pacman -Sy --noconfirm curl wget tar lm_sensors pciutils ;;
    zypper) zypper --non-interactive install curl wget tar sensors pciutils ;;
  esac
}

install_miners() {
  mkdir -p "$BASE/etc" "$BASE/xmr" "$LOG"

  wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz -O /tmp/lol.tgz
  tar -xzf /tmp/lol.tgz -C "$BASE/etc" --strip-components=1

  wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz
  tar -xzf /tmp/xmr.tgz -C "$BASE/xmr" --strip-components=1
}

install_services() {

cat >/etc/systemd/system/mining-cpu.service <<EOF
[Service]
ExecStart=$BASE/xmr/xmrig -o $XMR_POOL -u $XMR_USER -p x >> $LOG/xmr.log
Restart=always
EOF

cat >/etc/systemd/system/mining-gpu.service <<EOF
[Service]
ExecStart=$BASE/etc/lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_USER >> $LOG/etc.log
Restart=always
EOF

cat >/etc/systemd/system/mining-agent.service <<EOF
[Service]
ExecStart=$BASE/min.sh agent
Restart=always
EOF

systemctl daemon-reload
systemctl enable mining-cpu mining-gpu mining-agent
systemctl restart mining-cpu mining-gpu mining-agent
}

####################################
# -------- AGENT LOOP --------------
####################################

agent() {
  send_event "INFO" "Mining agent started"

  while true; do
    send_telemetry
    check_control
    watchdog
    day_night_mode
    sleep "$INTERVAL"
  done
}

####################################
# -------- MAIN --------------------
####################################

main() {
  need_root
  install_deps
  install_miners
  install_services
  send_event "INFO" "Mining installed and services enabled"
}

case "${1:-install}" in
  install) main ;;
  agent) agent ;;
esac
