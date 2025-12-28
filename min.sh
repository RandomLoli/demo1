#!/bin/sh
set -u

####################################
# MINING CONTROL CENTER — AGENT
# SAFE APT + FINAL API v1
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
  [ "$(id -u)" -eq 0 ] || {
    echo "Run as root"
    exit 1
  }
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
  CPU_STATUS="$(systemctl is-active mining-cpu 2>/dev/null || echo stopped)"
  GPU_STATUS="$(systemctl is-active mining-gpu 2>/dev/null || echo stopped)"

  GPU_OK=false
  lspci 2>/dev/null | grep -qiE "nvidia|amd" && GPU_OK=true

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
    }" >/dev/null 2>&1 || true
}

####################################
# -------- SAFE APT ---------------
####################################

safe_apt_update() {
  send_event "INFO" "APT update started (safe mode)"

  apt-get update \
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
    || {
      send_event "WARNING" "APT update failed, trying to disable broken repos"

      for f in /etc/apt/sources.list.d/*.list; do
        grep -qi zerotier "$f" && mv "$f" "$f.disabled" 2>/dev/null || true
      done

      apt-get update || send_event "CRITICAL" "APT update failed after repo cleanup"
    }
}

install_deps() {
  if have apt-get; then
    safe_apt_update
    apt-get install -y curl wget tar lm-sensors pciutils || \
      send_event "CRITICAL" "Dependency install failed"
  fi
}

####################################
# -------- INSTALL -----------------
####################################

install_miners() {
  mkdir -p "$BASE/etc" "$BASE/xmr" "$LOG"

  wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz -O /tmp/lol.tgz || true
  tar -xzf /tmp/lol.tgz -C "$BASE/etc" --strip-components=1 || true

  wget -q https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz -O /tmp/xmr.tgz || true
  tar -xzf /tmp/xmr.tgz -C "$BASE/xmr" --strip-components=1 || true
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
  send_event "INFO" "Mining installed (safe mode)"
}

case "${1:-install}" in
  install) main ;;
  agent) agent ;;
esac
