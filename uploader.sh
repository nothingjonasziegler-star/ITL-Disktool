#!/bin/bash
set -uo pipefail

DEVICE="$1"
DEV_SAFE=$(basename "$DEVICE")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIPE_DB="/tmp/wipe_db"
LOG="$SCRIPT_DIR/logs/disktoolitl.log"
CONFIG_FILE="$WIPE_DB/config.json"
SMART_FILE="$WIPE_DB/${DEV_SAFE}_smart.json"
STATE_FILE="$WIPE_DB/${DEV_SAFE}_state.json"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; }

if [ ! -f "$SMART_FILE" ]; then
    log "$DEVICE: Keine SMART-Datei gefunden — Upload übersprungen"
    exit 0
fi

if [ ! -f "$CONFIG_FILE" ]; then
    log "$DEVICE: Kein Server konfiguriert — Upload übersprungen"
    exit 0
fi

SERVER_URL=$(jq -r '.server_url // ""' "$CONFIG_FILE")

if [ -z "$SERVER_URL" ]; then
    log "$DEVICE: Kein Server konfiguriert — Upload übersprungen"
    exit 0
fi

PAYLOAD=$(jq '{device,type,size_gb,status,progress,smart_passed,timestamp}' "$STATE_FILE")

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    --max-time 10 \
    --connect-timeout 5)

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    log "$DEVICE: SMART-Daten erfolgreich hochgeladen (HTTP $HTTP_CODE)"
else
    log "$DEVICE: Upload fehlgeschlagen (HTTP $HTTP_CODE) — speichere lokal"
    cp "$SMART_FILE" "$WIPE_DB/${DEV_SAFE}_upload_fail.json"
fi
