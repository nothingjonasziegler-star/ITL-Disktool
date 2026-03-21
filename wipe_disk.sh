#!/bin/bash
set -uo pipefail

DEVICE="$1"
DEV_SAFE=$(basename "$DEVICE")
WIPE_DB="/tmp/wipe_db"
LOG="/var/log/disktoolitl/disktoolitl.log"
STATE_FILE="$WIPE_DB/${DEV_SAFE}_state.json"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; }

update_state() {
    local status="$1"
    local progress="$2"
    if [ -f "$STATE_FILE" ]; then
        TMP=$(jq --arg s "$status" --argjson p "$progress" \
              '.status = $s | .progress = $p' "$STATE_FILE")
        echo "$TMP" > "$STATE_FILE"
    fi
}

TOTAL=$(blockdev --getsize64 "$DEVICE")

update_state "WIPING" 0
log "$DEVICE: Starte Zero-Fill-Wipe (${TOTAL} Bytes)"

dd if=/dev/zero of="$DEVICE" bs=4M status=none &
DD_PID=$!

while kill -0 "$DD_PID" 2>/dev/null; do
    if [ -f /proc/$DD_PID/fdinfo/1 ]; then
        POS=$(grep 'pos:' /proc/$DD_PID/fdinfo/1 2>/dev/null | awk '{print $2}')
        if [ -n "$POS" ] && [ "$TOTAL" -gt 0 ]; then
            PCT=$(awk "BEGIN {printf \"%.1f\", $POS/$TOTAL*100}")
            update_state "WIPING" "$PCT"
        fi
    fi
    sleep 2
done

wait "$DD_PID"
DD_EXIT=$?

if [ "$DD_EXIT" -ne 0 ]; then
    log "$DEVICE: FEHLER beim Wipe (dd exit $DD_EXIT)"
    update_state "ERROR" 0
    exit 1
fi

log "$DEVICE: Wipe abgeschlossen — starte Verifikation"

VERIFY_OK=true
for OFFSET in 0 $((TOTAL / 2)) $((TOTAL - 4096)); do
    [ "$OFFSET" -lt 0 ] && OFFSET=0
    NON_ZERO=$(dd if="$DEVICE" bs=4096 count=1 skip=$((OFFSET / 4096)) 2>/dev/null \
               | tr -d '\000' | wc -c)
    if [ "$NON_ZERO" -gt 0 ]; then
        VERIFY_OK=false
        break
    fi
done

if $VERIFY_OK; then
    log "$DEVICE: Verifikation BESTANDEN → DONE"
    update_state "DONE" 100
else
    log "$DEVICE: Verifikation FEHLGESCHLAGEN → ERROR"
    update_state "ERROR" 0
fi
