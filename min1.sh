#!/bin/sh

#################################################
# STABLE MINING AGENT (REVIEWED)
# CPU: XMR (XMRig, Kryptex)
# GPU: ETC (lolMiner, Kryptex)
#################################################

### ===== BASIC =====
HOST="$(hostname)"
INTERVAL=30

# ===== TELEGRAM =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"
TG_API="https://api.telegram.org/bot${TG_TOKEN}/sendMessage"

tg() {
  curl -s --connect-timeout 10 \
    -X POST "$TG_API" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$1" >/dev/null 2>&1 || true
}

# ===== ALLOW CHECK =====
if [ "${ALLOW_MINING:-0}" != "1" ]; then
  tg "❌ [$HOST] ALLOW_MINING != 1, выход"
  exit 0
fi

# ===== NETWORK WAIT =====
sleep 10

tg "🚀 [$HOST] Mining agent starting"

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

#################################################
# INSTALLERS (ALWAYS REINSTALL)
#################################################

install_xmrig() {
  tg "📦 [$HOST] Installing XMRig"
  pkill xmrig 2>/dev/null || true
  rm -f "$BIN/cpu/xmrig"

  wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz || return 1
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1 || return 1
  chmod +x "$BIN/cpu/xmrig"
}

install_lolminer() {
  tg "📦 [$HOST] Installing lolMiner"
  pkill lolMiner 2>/dev/null || true
  rm -f "$BIN/gpu/lolMiner"

  wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz || return 1
  tar -xzf /tmp/lol.tgz -C "$BIN/gpu" --strip-components=1 || return 1
  chmod +x "$BIN/gpu/lolMiner"
}

#################################################
# CPU — XMR
#################################################

start_cpu() {
  pkill xmrig 2>/dev/null || true
  "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
  tg "⚙️ [$HOST] CPU XMR started"
}

#################################################
# GPU — ETC
#################################################

start_gpu() {
  pkill lolMiner 2>/dev/null || true
  "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$KRIPTEX.$HOST" \
    --ethstratum ETCPROXY \
    --apihost 127.0.0.1 --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
  tg "🔥 [$HOST] GPU ETC started"
}

#################################################
# HASHRATE
#################################################

get_cpu_hr() {
  curl -s http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+' | head -1 || echo 0
}

get_gpu_hr() {
  curl -s http://127.0.0.1:8080/summary \
    | grep -oE '"Performance":[ ]*[0-9]+(\.[0-9]+)?' \
    | grep -oE '[0-9]+(\.[0-9]+)?' || echo 0
}

#################################################
# AUTOSTART
#################################################

ensure_autostart() {
  crontab -l 2>/dev/null | grep -q min1.sh && return
  (crontab -l 2>/dev/null; echo "@reboot ALLOW_MINING=1 $BASE/min1.sh") | crontab -
}

#################################################
# WATCHDOG
#################################################

watchdog() {
  [ -f "$RUN/cpu.pid" ] || { start_cpu; tg "♻️ [$HOST] CPU restarted"; }
  [ -f "$RUN/gpu.pid" ] || { start_gpu; tg "♻️ [$HOST] GPU restarted"; }

  GPU_HR="$(get_gpu_hr | sed 's/\..*//')"
  if [ -n "$GPU_HR" ] && [ "$GPU_HR" -eq 0 ]; then
    start_gpu
    tg "⚠️ [$HOST] GPU HR=0, restart"
  fi
}

#################################################
# MAIN
#################################################

install_xmrig || tg "❌ [$HOST] XMRig install failed"
install_lolminer || tg "❌ [$HOST] lolMiner install failed"

ensure_autostart
start_cpu
start_gpu

tg "✅ [$HOST] Mining running"

while true; do
  watchdog
  sleep "$INTERVAL"
done
