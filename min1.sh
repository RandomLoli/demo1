#!/bin/sh
set -eu

#################################################
# UNIVERSAL MINING AGENT — XMR + ETC (KRYPTEX)
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOST="$(hostname)"
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG"

### Kryptex settings
KRIPTEX_USER="krxX3PVQVR"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"
ETC_WORKER="krxX3PVQVR.worker"

### Telegram
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

send_tg() {
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$1" >/dev/null 2>&1
}

#################################################
# INSTALL XMRIG (6.25.0 static)
#################################################

install_xmrig() {
  if [ ! -x "$BIN/cpu/xmrig" ]; then
    send_tg "⚙️ [$HOST] Installing XMRig"
    wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz || return
    tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1
    chmod +x "$BIN/cpu/xmrig"
  fi
}

#################################################
# INSTALL LOLMINER (1.98a)
#################################################

install_lolminer() {
  if [ ! -x "$BIN/gpu/lolMiner" ]; then
    send_tg "⚙️ [$HOST] Installing lolMiner 1.98a"
    wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz || return
    tar -xzf /tmp/lol.tgz -C "$BIN/gpu" --strip-components=1
    chmod +x "$BIN/gpu/lolMiner"
  fi
}

#################################################
# CPU — XMR
#################################################

start_cpu() {
  pkill xmrig >/dev/null 2>&1 || true
  nohup "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX_USER.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
}

cpu_hashrate() {
  curl -s http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' | grep -oE '[0-9]+' | head -1 || echo 0
}

#################################################
# GPU — ETC (lolMiner)
#################################################

start_gpu() {
  pkill lolMiner >/dev/null 2>&1 || true
  nohup "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$ETC_WORKER" \
    --pass x \
    --ethstratum ETCPROXY \
    --disable-dag-verify \
    --apihost 127.0.0.1 \
    --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
}

gpu_hashrate() {
  curl -s http://127.0.0.1:8080/summary \
    | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?' || echo 0
}

#################################################
# AUTOSTART
#################################################

enable_autostart() {
  crontab -l 2>/dev/null | grep -q min1.sh || \
    (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min1.sh") | crontab -

  if command -v systemctl >/dev/null 2>&1; then
cat <<EOF | sudo tee /etc/systemd/system/mining.service >/dev/null
[Unit]
Description=Mining Agent
After=network.target

[Service]
ExecStart=$BASE/min1.sh
Restart=always
Environment=ALLOW_MINING=1

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable mining.service >/dev/null 2>&1
  fi
}

#################################################
# WATCHDOG
#################################################

watchdog() {
  [ -f "$RUN/cpu.pid" ] || { start_cpu; send_tg "♻️ [$HOST] CPU Restarted"; }
  [ -f "$RUN/gpu.pid" ] || { start_gpu; send_tg "♻️ [$HOST] GPU Restarted"; }

  CPU_HR=$(cpu_hashrate)
  GPU_HR=$(gpu_hashrate)

  if [ "$(printf "%.0f" "$GPU_HR")" -eq 0 ]; then
    start_gpu
    send_tg "⚠️ [$HOST] GPU Hashrate zero → Restart"
  fi
}

#################################################
# MAIN
#################################################

send_tg "🚀 [$HOST] Mining Setup Starting"
install_xmrig
install_lolminer
enable_autostart
start_cpu
start_gpu
send_tg "✅ [$HOST] Mining Started"

while true; do
  watchdog
  sleep 30
done
