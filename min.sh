#!/bin/sh
set -eu

### ================= CONFIG =================
KRIPTEX_USERNAME="krxX3PVQVR"
WORKER_NAME="worker"

ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

TELEGRAM_BOT_TOKEN="PUT_YOUR_TOKEN_HERE"
TELEGRAM_CHAT_ID="PUT_YOUR_CHAT_ID_HERE"

BASE_DIR="/opt/mining"
LOG_DIR="/var/log"

ETC_USERNAME="${KRIPTEX_USERNAME}.${WORKER_NAME}"
XMR_USERNAME="${KRIPTEX_USERNAME}.${WORKER_NAME}"
### ==========================================

ERRORS=""

have() { command -v "$1" >/dev/null 2>&1; }
report() { ERRORS="${ERRORS}$1 "; }

# ---------- Telegram helpers ----------
tg_send() {
    txt="$1"
    [ -z "$TELEGRAM_BOT_TOKEN" ] && return 0
    curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${txt}" \
        -d "parse_mode=HTML" >/dev/null 2>&1 || true
}

tg_send_chunks() {
    title="$1"
    file="$2"
    [ ! -f "$file" ] && tg_send "❌ <b>$title</b>%0Alog not found" && return

    sed -n '1,200p' "$file" | while IFS= read -r line; do
        chunk="${chunk}${line}\n"
        [ "${#chunk}" -gt 3500 ] && { tg_send "<b>$title</b>%0A<pre>$chunk</pre>"; chunk=""; }
    done

    [ -n "$chunk" ] && tg_send "<b>$title</b>%0A<pre>$chunk</pre>"
}

# ---------- checks ----------
need_root() { [ "$(id -u)" -eq 0 ] || { report "E01"; exit 1; }; }
arch_check() { uname -m | grep -Eq "x86_64|amd64" || { report "E02"; exit 1; }; }

detect_pm() {
    for pm in apt-get dnf yum pacman zypper; do
        have "$pm" && { PM="$pm"; return; }
    done
    report "E03"; exit 1
}

install_deps() {
    case "$PM" in
        apt-get) apt-get update && apt-get install -y curl wget tar cron ;;
        dnf|yum) $PM install -y curl wget tar cronie ;;
        pacman) pacman -Sy --noconfirm curl wget tar cronie ;;
        zypper) zypper --non-interactive install curl wget tar cron ;;
        *) report "E04"; exit 1 ;;
    esac
}

fetch() {
    if have curl; then curl -fsSL "$1" -o "$2"
    else wget -q "$1" -O "$2"
    fi
}

install_miners() {
    mkdir -p "$BASE_DIR/etc" "$BASE_DIR/xmr"

    fetch https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz \
        "$BASE_DIR/etc/lol.tgz" || report "E05"
    tar -xzf "$BASE_DIR/etc/lol.tgz" -C "$BASE_DIR/etc" --strip-components=1 || report "E05"

    fetch https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz \
        "$BASE_DIR/xmr/xmr.tgz" || report "E06"
    tar -xzf "$BASE_DIR/xmr/xmr.tgz" -C "$BASE_DIR/xmr" --strip-components=1 || report "E06"

    cat > "$BASE_DIR/etc/start.sh" <<EOF
#!/bin/sh
cd $BASE_DIR/etc && ./lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_USERNAME
EOF

    cat > "$BASE_DIR/xmr/start.sh" <<EOF
#!/bin/sh
cd $BASE_DIR/xmr && ./xmrig -o $XMR_POOL -u $XMR_USERNAME -p x
EOF

    chmod +x "$BASE_DIR/etc/start.sh" "$BASE_DIR/xmr/start.sh"
}

start_miners() {
    "$BASE_DIR/etc/start.sh" > "$LOG_DIR/etc-miner.log" 2>&1 &
    "$BASE_DIR/xmr/start.sh" > "$LOG_DIR/xmr-miner.log" 2>&1 &
    sleep 5
    pgrep -f lolMiner >/dev/null || report "E09"
    pgrep -f xmrig >/dev/null || report "E09"
    [ -s "$LOG_DIR/etc-miner.log" ] || report "E10"
    [ -s "$LOG_DIR/xmr-miner.log" ] || report "E10"
}

# ---------- main ----------
main() {
    need_root
    arch_check
    detect_pm
    install_deps
    install_miners
    start_miners

    if [ -z "$ERRORS" ]; then
        tg_send "✅ <b>УСТАНОВКА OK</b>%0AHost: <code>$(hostname)</code>"
    else
        tg_send "❌ <b>УСТАНОВКА С ОШИБКАМИ</b>%0AКоды: <code>$ERRORS</code>"
    fi

    # Логи сразу в TG
    tg_send_chunks "ETC log (last lines)" "$LOG_DIR/etc-miner.log"
    tg_send_chunks "XMR log (last lines)" "$LOG_DIR/xmr-miner.log"
}

main
