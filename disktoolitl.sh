#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p /tmp/wipe_db
mkdir -p /var/log/disktoolitl

bash "$SCRIPT_DIR/network_init.sh"

python3 "$SCRIPT_DIR/disktoolitl.py" &
WEB_PID=$!

bash "$SCRIPT_DIR/disk_monitor.sh" &
MON_PID=$!

trap "kill \$WEB_PID \$MON_PID 2>/dev/null; exit" INT TERM EXIT

bash "$SCRIPT_DIR/splash.sh"
