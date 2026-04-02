#!/bin/bash
set -uo pipefail

DEVICE="$1"
DEV_SAFE=$(basename "$DEVICE")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIPE_DB="/tmp/wipe_db"
LOG_DIR="$SCRIPT_DIR/logs"
LOG="$LOG_DIR/disktoolitl.log"
STATE_FILE="$WIPE_DB/${DEV_SAFE}_state.json"
CERT_DIR="$LOG_DIR/certificates"

mkdir -p "$LOG_DIR"
mkdir -p "$CERT_DIR"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; }

update_state() {
    local status="$1"
    local progress="$2"
    local extra="${3:-}"
    if [ -f "$STATE_FILE" ]; then
        if [ -n "$extra" ]; then
            TMP=$(jq --arg s "$status" --argjson p "$progress" --arg e "$extra" \
                  '.status = $s | .progress = $p | .extra = $e' "$STATE_FILE")
        else
            TMP=$(jq --arg s "$status" --argjson p "$progress" \
                  '.status = $s | .progress = $p | .extra = ""' "$STATE_FILE")
        fi
        echo "$TMP" > "$STATE_FILE"
    fi
}

for part in "${DEVICE}"[0-9]* "${DEVICE}p"[0-9]*; do
    [ -b "$part" ] || continue
    if mountpoint -q "$part" 2>/dev/null || grep -q "$part" /proc/mounts 2>/dev/null; then
        log "$DEVICE: Unmount $part"
        umount -f "$part" 2>/dev/null || true
    fi
done
if grep -q "$DEVICE" /proc/mounts 2>/dev/null; then
    log "$DEVICE: Unmount $DEVICE"
    umount -f "$DEVICE" 2>/dev/null || true
fi

TOTAL=$(blockdev --getsize64 "$DEVICE")
TOTAL_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL/1073741824}")

PASSES=("zero" "ones" "random")
PASS_SOURCES=("/dev/zero" "" "/dev/urandom")
PASS_COUNT=${#PASSES[@]}
WIPE_START=$(date +%s)

log "$DEVICE: Starte DOD 3-Pass-Wipe (${TOTAL_GB}GB)"

for (( p=0; p<PASS_COUNT; p++ )); do
    PASS_NAME="${PASSES[$p]}"
    PASS_NUM=$((p+1))
    log "$DEVICE: Pass $PASS_NUM/$PASS_COUNT ($PASS_NAME)"

    if [ "$PASS_NAME" = "ones" ]; then
        tr '\000' '\377' < /dev/zero | dd of="$DEVICE" bs=4M status=none 2>/dev/null &
        DD_PID=$!
    else
        dd if="${PASS_SOURCES[$p]}" of="$DEVICE" bs=4M status=none &
        DD_PID=$!
    fi

    PASS_START=$(date +%s)

    while kill -0 "$DD_PID" 2>/dev/null; do
        POS=0
        if [ -f /proc/$DD_PID/fdinfo/1 ]; then
            POS=$(grep 'pos:' /proc/$DD_PID/fdinfo/1 2>/dev/null | awk '{print $2}')
            POS=${POS:-0}
        fi

        if [ "$TOTAL" -gt 0 ] && [ "$POS" -gt 0 ]; then
            PASS_PCT=$(awk "BEGIN {printf \"%.1f\", $POS/$TOTAL*100}")
            OVERALL=$(awk "BEGIN {printf \"%.1f\", ($p*100 + $POS/$TOTAL*100) / $PASS_COUNT}")

            NOW=$(date +%s)
            ELAPSED=$((NOW - PASS_START))
            if [ "$ELAPSED" -gt 2 ]; then
                SPEED=$(awk "BEGIN {printf \"%.0f\", $POS/$ELAPSED/1048576}")
                REMAINING_BYTES=$((TOTAL - POS))
                ETA_S=$(awk "BEGIN {printf \"%.0f\", $REMAINING_BYTES / ($POS/$ELAPSED)}")
                ETA_MIN=$((ETA_S / 60))
                ETA_SEC=$((ETA_S % 60))
                EXTRA="Pass ${PASS_NUM}/${PASS_COUNT} | ${SPEED}MB/s | ETA ${ETA_MIN}m${ETA_SEC}s"
            else
                EXTRA="Pass ${PASS_NUM}/${PASS_COUNT}"
            fi

            update_state "WIPING" "$OVERALL" "$EXTRA"
        else
            update_state "WIPING" "$(awk "BEGIN {printf \"%.1f\", $p*100/$PASS_COUNT}")" "Pass ${PASS_NUM}/${PASS_COUNT}"
        fi

        sleep 2
    done

    wait "$DD_PID" || true
done

WIPE_END=$(date +%s)
WIPE_DURATION=$((WIPE_END - WIPE_START))
WIPE_MIN=$((WIPE_DURATION / 60))

log "$DEVICE: 3-Pass-Wipe abgeschlossen in ${WIPE_MIN}min — starte Verifikation"
update_state "VERIFY" 99 "Verifikation laeuft..."

VERIFY_OK=true
VERIFY_POINTS=10
for (( v=0; v<VERIFY_POINTS; v++ )); do
    OFFSET=$(awk "BEGIN {printf \"%.0f\", $TOTAL * $v / $VERIFY_POINTS}")
    BLOCK=$((OFFSET / 4096))
    NON_ZERO=$(dd if="$DEVICE" bs=4096 count=1 skip=$BLOCK 2>/dev/null \
               | tr -d '\000' | wc -c)
    if [ "$NON_ZERO" -gt 0 ]; then
        VERIFY_OK=false
        log "$DEVICE: Verifikation FEHLGESCHLAGEN bei Offset $OFFSET"
        break
    fi
done

MODEL=$(jq -r '.model // "N/A"' "$STATE_FILE" 2>/dev/null)
SERIAL=$(jq -r '.serial // "N/A"' "$STATE_FILE" 2>/dev/null)
DISK_TYPE=$(jq -r '.type // "N/A"' "$STATE_FILE" 2>/dev/null)

if $VERIFY_OK; then
    log "$DEVICE: Verifikation BESTANDEN -> DONE"
    update_state "DONE" 100 "3-Pass DOD | ${WIPE_MIN}min"
    printf '\a'

    CERT_FILE="$CERT_DIR/${DEV_SAFE}_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "========================================================"
        echo "        WIPE-ZERTIFIKAT / DISK ERASURE REPORT"
        echo "========================================================"
        echo ""
        echo "  Device:        $DEVICE"
        echo "  Typ:           $DISK_TYPE"
        echo "  Modell:        $MODEL"
        echo "  Seriennummer:  $SERIAL"
        echo "  Kapazitaet:    ${TOTAL_GB}GB ($TOTAL Bytes)"
        echo ""
        echo "  Methode:       DOD 5220.22-M (3-Pass)"
        echo "    Pass 1:      Zero-Fill (0x00)"
        echo "    Pass 2:      One-Fill  (0xFF)"
        echo "    Pass 3:      Random"
        echo ""
        echo "  Start:         $(date -d @$WIPE_START '+%Y-%m-%d %H:%M:%S')"
        echo "  Ende:          $(date -d @$WIPE_END '+%Y-%m-%d %H:%M:%S')"
        echo "  Dauer:         ${WIPE_MIN} Minuten"
        echo ""
        echo "  Verifikation:  BESTANDEN ($VERIFY_POINTS Pruefpunkte)"
        echo "  Ergebnis:      SICHER GELOESCHT"
        echo ""
        echo "  Hostname:      $(hostname)"
        echo "  Erstellt:      $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================================"
    } > "$CERT_FILE"
    log "$DEVICE: Wipe-Zertifikat erstellt: $CERT_FILE"
else
    log "$DEVICE: Verifikation FEHLGESCHLAGEN -> ERROR"
    update_state "ERROR" 0 "Verifikation fehlgeschlagen"
    printf '\a\a\a'
fi
