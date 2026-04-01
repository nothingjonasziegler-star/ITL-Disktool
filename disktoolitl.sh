#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

mkdir -p /tmp/wipe_db
mkdir -p "$SCRIPT_DIR/logs"

bash "$SCRIPT_DIR/network_init.sh"

bash "$SCRIPT_DIR/disk_monitor.sh" &
MON_PID=$!

trap "kill \$MON_PID 2>/dev/null; exit" INT TERM EXIT

bash "$SCRIPT_DIR/splash.sh"
