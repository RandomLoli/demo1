#!/bin/sh
set -eu

### ================= CONFIG =================
KRIPTEX_USERNAME="krxX3PVQVR"
WORKER_NAME="$(hostname)"

ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

BASE_DIR="/opt/mining"
LOG_DIR="/var/log/mining"

ETC_USERNAME="${KRIPTEX_USERNAME}.${WORKER_NAME}"
XMR_USERNAME="${KRIPTEX_USERNAME}.${WORKER_NAME}"
### ==========================================

ERRORS=""

have() { command -v "$1" >/dev/null 2>&1; }
report() { ERRORS="${ERRORS}$1 "; }

# ---------- Telegram ----------
tg_send() {
    [ -z "$TELEGRAM_BOT_TOKEN" ] && return 0
    curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$1" >/dev/null 2>&1 || true
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
        apt-get)
            apt-get update || true
            apt-get install -y curl wget tar cron || report "E04"
        ;;
        dnf|yum) $PM install -y curl wget tar cronie || report "E04" ;;
        pacman) pacman -Sy --noconfirm curl wget tar cronie || report "E04" ;;
        zypper) zypper --non-interactive install curl wget tar cron || report "E04" ;;
    esac
}

fetch() {
    url="$1"
    out="$2"
    have curl && curl -fsSL "$url" -o "$out" || wget -q "$url" -O "$out"
    [ -s "$out" ] || return 1
}

install_miners() {
    mkdir -p "$BASE_DIR/etc" "$BASE_DIR/xmr" "$LOG_DIR"

    fetch https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz \
        "$BASE_DIR/etc/lol.tgz" || { report "E05"; return; }

    tar -xzf "$BASE_DIR/etc/lol.tgz" -C "$BASE_DIR/etc" --strip-components=1 || report "E05"

    fetch https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz \
        "$BASE_DIR/xmr/xmr.tgz" || { report "E06"; return; }

    tar -xzf "$BASE_DIR/xmr/xmr.tgz" -C "$BASE_DIR/xmr" --strip-components=1 || report "E06"

    cat > "$BASE_DIR/etc/start.sh" <<EOF
#!/bin/sh
cd $BASE_DIR/etc || exit 1
nohup ./lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_USERNAME >> $LOG_DIR/etc.log 2>&1 &
EOF

    cat > "$BASE_DIR/xmr/start.sh" <<EOF
#!/bin/sh
cd $BASE_DIR/xmr || exit 1
nohup ./xmrig -o $XMR_POOL -u $XMR_USERNAME -p x >> $LOG_DIR/xmr.log 2>&1 &
EOF

    chmod +x "$BASE_DIR/etc/start.sh" "$BASE_DIR/xmr/start.sh"
}

start_miners() {
    [ -n "$ERRORS" ] && {
        echo "❌ Errors detected: $ERRORS"
        exit 1
    }

    pkill -f lolMiner || true
    pkill -f xmrig || true

    "$BASE_DIR/etc/start.sh"
    "$BASE_DIR/xmr/start.sh"

    sleep 5
    pgrep -f lolMiner >/dev/null || report "E07"
    pgrep -f xmrig >/dev/null || report "E08"
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
        tg_send "✅ Mining started on $(hostname)"
        echo "✅ Mining running"
    else
        tg_send "❌ Errors: $ERRORS"
        echo "❌ Errors: $ERRORS"
        exit 1
    fi
}

main
