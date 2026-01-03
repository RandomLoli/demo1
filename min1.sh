#!/usr/bin/env bash

###############################################################################
# PROFESSIONAL MINING AGENT (FIXED)
# CPU: XMR (XMRig)
# GPU: ETC (lolMiner, Kryptex)
# Control: Telegram (HTML, safe)
###############################################################################

set -o pipefail

# ===================== ENV =====================
ALLOW_MINING="${ALLOW_MINING:-0}"
[ "$ALLOW_MINING" = "1" ] || exit 0

HOST="$(hostname)"
BASE="$HOME/.mining"
BIN_CPU="$BASE/bin/cpu"
BIN_GPU="$BASE/bin/gpu"
LOG="$BASE/log"
mkdir -p "$BIN_CPU" "$BIN_GPU" "$LOG"

# ===================== KRYPTEX =====================
KRIPTEX_USER="krxX3PVQVR"
ETC_WORKER="krxX3PVQVR.worker"
XMR_POOL="xmr.kryptex.network:7029"
ETC_POOL="etc.kryptex.network:7033"

# ===================== TELEGRAM =====================
TG_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TG_CHAT="5336452267"
TG_API="https://api.telegram.org/bot${TG_TOKEN}/sendMessage"

tg() {
  local text="$1"
  curl -fsS --connect-timeout 10 \
    -X POST "$TG_API" \
    -d "chat_id=$TG_CHAT" \
    -d "parse_mode=HTML" \
    --data-urlencode "text=$text" >/dev/null || true
}

# ===================== NETWORK WAIT =====================
for _ in {1..15}; do
  curl -fsS https://api.telegram.org >/dev/null 2>&1 && break
  sleep 4
done

tg "🚀 <b>$HOST</b>: запуск установки майнинга"

# ===================== CLEANUP =====================
pkill xmrig 2>/dev/null || true
pkill lolMiner 2>/dev/null || true
rm -rf "$BIN_CPU"/* "$BIN_GPU"/*

tg "♻️ <b>$HOST</b>: старые процессы очищены"

# ===================== INSTALL XMRIG =====================
tg "📦 <b>$HOST</b>: установка XMRig"

XMR_OK=0
for URL in \
  "https://xmrig.com/download/xmrig-6.25.0-linux-static-x64.tar.gz" \
  "https://github.com/xmrig/xmrig/releases/download/v6.25.0/xmrig-6.25.0-linux-static-x64.tar.gz"
do
  if wget -q "$URL" -O /tmp/xmrig.tgz &&
     tar -xzf /tmp/xmrig.tgz -C "$BIN_CPU" --strip-components=1 &&
     chmod +x "$BIN_CPU/xmrig"
  then
    XMR_OK=1
    break
  fi
done

if [ "$XMR_OK" != "1" ] || [ ! -x "$BIN_CPU/xmrig" ]; then
  tg "❌ <b>$HOST</b>: ошибка установки XMRig"
  exit 1
fi

tg "✅ <b>$HOST</b>: XMRig установлен"

# ===================== INSTALL LOLMINER =====================
tg "📦 <b>$HOST</b>: установка lolMiner"

LOL_OK=0
for URL in \
  "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98a/lolMiner_v1.98a_Lin64.tar.gz" \
  "https://objects.githubusercontent.com/github-production-release-asset-2e65be/LOL"
do
  if wget -q "$URL" -O /tmp/lolminer.tgz &&
     tar -xzf /tmp/lolminer.tgz -C "$BIN_GPU" --strip-components=1 &&
     chmod +x "$BIN_GPU/lolMiner"
  then
    LOL_OK=1
    break
  fi
done

if [ "$LOL_OK" != "1" ] || [ ! -x "$BIN_GPU/lolMiner" ]; then
  tg "❌ <b>$HOST</b>: ошибка установки lolMiner"
  exit 1
fi

tg "✅ <b>$HOST</b>: lolMiner установлен"

# ===================== START XMR =====================
"$BIN_CPU/xmrig" \
  -o "$XMR_POOL" \
  -u "$KRIPTEX_USER.$HOST" -p x \
  >>"$LOG/xmrig.log" 2>&1 &

sleep 4
pgrep xmrig >/dev/null && \
  tg "⚙️ <b>$HOST</b>: CPU → XMR запущен" || \
  tg "❌ <b>$HOST</b>: XMR не запустился"

# ===================== START ETC =====================
"$BIN_GPU/lolMiner" \
  --algo ETCHASH \
  --pool "$ETC_POOL" \
  --user "$ETC_WORKER" \
  --pass x \
  --ethstratum ETCPROXY \
  >>"$LOG/lolminer.log" 2>&1 &

sleep 6
pgrep lolMiner >/dev/null && \
  tg "🔥 <b>$HOST</b>: GPU → ETC запущен" || \
  tg "❌ <b>$HOST</b>: ETC не запустился"

tg "✅ <b>$HOST</b>: установка завершена, майнинг активен"

# ===================== WATCHDOG =====================
while true; do
  sleep 30
  pgrep xmrig >/dev/null || tg "⚠️ <b>$HOST</b>: XMR процесс упал"
  pgrep lolMiner >/dev/null || tg "⚠️ <b>$HOST</b>: ETC процесс упал"
done
