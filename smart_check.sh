#!/bin/bash
set -uo pipefail

DEVICE="$1"
DEV_SAFE=$(basename "$DEVICE")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIPE_DB="/tmp/wipe_db"
LOG_DIR="$SCRIPT_DIR/logs"
LOG="$LOG_DIR/disktoolitl.log"
STATE_FILE="$WIPE_DB/${DEV_SAFE}_state.json"
SMART_FILE="$WIPE_DB/${DEV_SAFE}_smart.json"

mkdir -p "$WIPE_DB"
mkdir -p "$LOG_DIR"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; logger -t disktoolitl "$1" 2>/dev/null || true; }

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

ROTATION=$(echo "$SMART_JSON" | jq -r '.rotation_rate // -1')
SMART_RAW=$(echo "$SMART_JSON" | jq -r '.smart_status.passed // "null"')
TEMP=$(echo "$SMART_JSON" | jq -r '.temperature.current // "null"')
POWER_ON_H=$(echo "$SMART_JSON" | jq -r '.power_on_time.hours // "null"')
MODEL=$(echo "$SMART_JSON" | jq -r '.model_name // ""')
SERIAL=$(echo "$SMART_JSON" | jq -r '.serial_number // ""')

if [[ "$DEVICE" == /dev/nvme* ]]; then
  DISK_TYPE="NVMe"
elif [ "$ROTATION" = "0" ]; then
  DISK_TYPE="SSD"
else
  DISK_TYPE="HDD"
fi

TRANSPORT=$(lsblk -dno TRAN "$DEVICE" 2>/dev/null || echo "")
IS_USB="false"
[ "$TRANSPORT" = "usb" ] && IS_USB="true"
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
  --argjson size_gb      "$SIZE_GB" \
  --arg status  "SMART" \
  --argjson progress     0 \
  --argjson smart_passed "$SMART_PASSED" \
  --argjson temp         "${TEMP:-null}" \
  --argjson power_hours  "${POWER_ON_H:-null}" \
  --arg model    "$MODEL" \
  --arg serial   "$SERIAL" \
  --arg transport "$TRANSPORT" \
  --argjson is_usb "$IS_USB" \
  --arg extra   "" \
  --arg timestamp "$(date -Iseconds)" \
  '{device:$device,type:$type,model:$model,serial:$serial,
    size_gb:$size_gb,status:$status,progress:$progress,
    smart_passed:$smart_passed,temp:$temp,power_hours:$power_hours,
    transport:$transport,is_usb:$is_usb,
    extra:$extra,timestamp:$timestamp}' \
  > "$STATE_FILE"

STATUS_STR="UNKNOWN"
[ "$SMART_PASSED" = "true"  ] && STATUS_STR="PASSED"
[ "$SMART_PASSED" = "false" ] && STATUS_STR="FAILED"

log "$DEVICE: SMART ${DISK_TYPE} ${MODEL} ${SERIAL} → ${STATUS_STR}"
