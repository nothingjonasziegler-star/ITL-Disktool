#!/bin/bash
set -uo pipefail

DEVICE="$1"
DEV_SAFE=$(basename "$DEVICE")
WIPE_DB="/tmp/wipe_db"
LOG="/var/log/disktoolitl/disktoolitl.log"
STATE_FILE="$WIPE_DB/${DEV_SAFE}_state.json"
SMART_FILE="$WIPE_DB/${DEV_SAFE}_smart.json"

mkdir -p "$WIPE_DB"
mkdir -p "$(dirname "$LOG")"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; }

jq -n \
  --arg device   "$DEVICE" \
  --arg type     "UNKNOWN" \
  --arg model    "" \
  --arg serial   "" \
  --argjson size_gb    0 \
  --arg status   "SMART" \
  --argjson progress   0 \
  --argjson smart_passed "null" \
  --arg timestamp "$(date -Iseconds)" \
  '{device:$device,type:$type,model:$model,serial:$serial,
    size_gb:$size_gb,status:$status,progress:$progress,
    smart_passed:$smart_passed,timestamp:$timestamp}' \
  > "$STATE_FILE"

log "$DEVICE: Lese SMART-Daten"

SMART_JSON=$(smartctl -a -j "$DEVICE" 2>/dev/null || echo '{}')
echo "$SMART_JSON" > "$SMART_FILE"

MODEL=$(echo "$SMART_JSON"    | jq -r '.model_name    // ""')
SERIAL=$(echo "$SMART_JSON"   | jq -r '.serial_number // ""')
ROTATION=$(echo "$SMART_JSON" | jq -r '.rotation_rate // -1')
SMART_RAW=$(echo "$SMART_JSON" | jq -r '.smart_status.passed // "null"')

if [ "$ROTATION" = "0" ]; then
    DISK_TYPE="SSD"
else
    DISK_TYPE="HDD"
fi

SIZE_BYTES=$(blockdev --getsize64 "$DEVICE" 2>/dev/null || echo 0)
SIZE_GB=$(awk "BEGIN {printf \"%.1f\", $SIZE_BYTES/1073741824}")

if [ "$SMART_RAW" = "true" ]; then
    SMART_PASSED="true"
elif [ "$SMART_RAW" = "false" ]; then
    SMART_PASSED="false"
else
    SMART_PASSED="null"
fi

jq -n \
  --arg device  "$DEVICE" \
  --arg type    "$DISK_TYPE" \
  --arg model   "$MODEL" \
  --arg serial  "$SERIAL" \
  --argjson size_gb      "$SIZE_GB" \
  --arg status  "SMART" \
  --argjson progress     0 \
  --argjson smart_passed "$SMART_PASSED" \
  --arg timestamp "$(date -Iseconds)" \
  '{device:$device,type:$type,model:$model,serial:$serial,
    size_gb:$size_gb,status:$status,progress:$progress,
    smart_passed:$smart_passed,timestamp:$timestamp}' \
  > "$STATE_FILE"

STATUS_STR="UNKNOWN"
[ "$SMART_PASSED" = "true"  ] && STATUS_STR="PASSED"
[ "$SMART_PASSED" = "false" ] && STATUS_STR="FAILED"

log "$DEVICE: SMART ${DISK_TYPE} ${MODEL} ${SERIAL} → ${STATUS_STR}"
