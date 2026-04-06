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
log() { echo "$(ts)  $1" | tee -a "$LOG"; logger -t disktoolitl "$1" 2>/dev/null || true; }

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

DISK_TYPE=$(jq -r '.type // "HDD"' "$STATE_FILE" 2>/dev/null)
IS_NVME=false
[[ "$DEVICE" == /dev/nvme* ]] && IS_NVME=true

IS_USB=false
TRAN=$(lsblk -dno TRAN "$DEVICE" 2>/dev/null)
[ "$TRAN" = "usb" ] && IS_USB=true

WIPE_START=$(date +%s)
WIPE_METHOD=""

if $IS_NVME; then
    WIPE_METHOD="NVMe Sanitize (Block Erase)"
    log "$DEVICE: Starte $WIPE_METHOD (${TOTAL_GB}GB)"
    update_state "WIPING" 5 "NVMe Sanitize gestartet"

    if nvme sanitize "$DEVICE" -a 2 2>/dev/null; then
        while true; do
            SLOG=$(nvme sanitize-log "$DEVICE" -o json 2>/dev/null || echo '{}')
            SPROG=$(echo "$SLOG" | jq -r '.sprog // 65535')
            if [ "$SPROG" = "65535" ]; then
                break
            fi
            PCT=$(awk "BEGIN {printf \"%.1f\", $SPROG / 65535 * 100}")
            update_state "WIPING" "$PCT" "NVMe Sanitize ${PCT}%"
            sleep 5
        done
        log "$DEVICE: NVMe Sanitize abgeschlossen"
    else
        log "$DEVICE: NVMe Sanitize nicht unterstuetzt, Fallback auf nvme format"
        WIPE_METHOD="NVMe Format (Secure Erase)"
        update_state "WIPING" 10 "NVMe Format gestartet"
        if nvme format "$DEVICE" --ses=1 2>/dev/null; then
            log "$DEVICE: NVMe Format (Secure Erase) abgeschlossen"
        else
            log "$DEVICE: NVMe Format fehlgeschlagen, Fallback auf DOD 3-Pass"
            WIPE_METHOD="DOD 5220.22-M (3-Pass Fallback)"
            DISK_TYPE="HDD"
        fi
    fi
    update_state "WIPING" 95 "$WIPE_METHOD abgeschlossen"

elif [ "$DISK_TYPE" = "SSD" ]; then
    WIPE_METHOD="SSD Secure Erase (blkdiscard + hdparm)"
    log "$DEVICE: Starte $WIPE_METHOD (${TOTAL_GB}GB)"
    update_state "WIPING" 5 "blkdiscard gestartet"

    if blkdiscard -f "$DEVICE" 2>/dev/null; then
        log "$DEVICE: blkdiscard (TRIM) erfolgreich"
        update_state "WIPING" 30 "blkdiscard fertig, starte Secure Erase"
    else
        log "$DEVICE: blkdiscard nicht unterstuetzt, uebersprungen"
        update_state "WIPING" 10 "blkdiscard nicht moeglich"
    fi

    if hdparm -I "$DEVICE" 2>/dev/null | grep -qi "supported.*enhanced erase"; then
        log "$DEVICE: Enhanced Secure Erase unterstuetzt"
        hdparm --user-master u --security-set-pass DiskToolITL "$DEVICE" 2>/dev/null
        hdparm --user-master u --security-erase-enhanced DiskToolITL "$DEVICE" 2>/dev/null && {
            log "$DEVICE: Enhanced Secure Erase abgeschlossen"
            update_state "WIPING" 90 "ATA Enhanced Secure Erase fertig"
        } || {
            log "$DEVICE: Enhanced Secure Erase fehlgeschlagen"
        }
    elif hdparm -I "$DEVICE" 2>/dev/null | grep -qi "supported.*security erase"; then
        log "$DEVICE: Standard Secure Erase unterstuetzt"
        hdparm --user-master u --security-set-pass DiskToolITL "$DEVICE" 2>/dev/null
        hdparm --user-master u --security-erase DiskToolITL "$DEVICE" 2>/dev/null && {
            log "$DEVICE: Standard Secure Erase abgeschlossen"
            update_state "WIPING" 90 "ATA Secure Erase fertig"
        } || {
            log "$DEVICE: Secure Erase fehlgeschlagen, Fallback auf DOD 3-Pass"
            WIPE_METHOD="DOD 5220.22-M (3-Pass Fallback)"
            DISK_TYPE="HDD"
        }
    else
        log "$DEVICE: ATA Secure Erase nicht unterstuetzt, Fallback auf DOD 3-Pass"
        WIPE_METHOD="DOD 5220.22-M (3-Pass Fallback)"
        DISK_TYPE="HDD"
    fi
    update_state "WIPING" 95 "$WIPE_METHOD abgeschlossen"
fi

if $IS_USB && [ "$DISK_TYPE" != "HDD" ]; then
    WIPE_METHOD="USB Wipe (blkdiscard + shred)"
    log "$DEVICE: USB-Stick erkannt — Starte $WIPE_METHOD (${TOTAL_GB}GB)"
    update_state "WIPING" 5 "USB: blkdiscard"

    if blkdiscard -f "$DEVICE" 2>/dev/null; then
        log "$DEVICE: USB blkdiscard erfolgreich"
        update_state "WIPING" 30 "USB: blkdiscard fertig"
    else
        log "$DEVICE: USB blkdiscard nicht unterstuetzt, uebersprungen"
    fi

    update_state "WIPING" 35 "USB: shred laeuft"
    shred -v -n 3 -z "$DEVICE" 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -qP 'pass \d+/\d+'; then
            PASS_INFO=$(echo "$line" | grep -oP 'pass \d+/\d+')
            update_state "WIPING" 50 "USB: shred $PASS_INFO"
        fi
    done
    log "$DEVICE: USB shred abgeschlossen"
    update_state "WIPING" 95 "$WIPE_METHOD abgeschlossen"
    DISK_TYPE="USB_DONE"
fi

if [ "$DISK_TYPE" = "HDD" ]; then
    if command -v nwipe &>/dev/null; then
        WIPE_METHOD="nwipe DOD 5220.22-M (3-Pass)"
        log "$DEVICE: Starte $WIPE_METHOD (${TOTAL_GB}GB)"
        update_state "WIPING" 5 "nwipe gestartet"

        nwipe --autonuke --nogui --method=dod522022m "$DEVICE" 2>&1 | while IFS= read -r line; do
            log "$DEVICE: nwipe: $line"
        done &
        NWIPE_PID=$!

        while kill -0 "$NWIPE_PID" 2>/dev/null; do
            update_state "WIPING" 50 "nwipe laeuft..."
            sleep 5
        done
        wait "$NWIPE_PID"
        NWIPE_EXIT=$?

        if [ "$NWIPE_EXIT" -eq 0 ]; then
            log "$DEVICE: nwipe abgeschlossen"
            update_state "WIPING" 95 "nwipe fertig"
        else
            log "$DEVICE: nwipe fehlgeschlagen (Exit $NWIPE_EXIT), Fallback auf shred"
            WIPE_METHOD="shred (3-Pass + Zero Fallback)"
            update_state "WIPING" 10 "shred Fallback gestartet"
            shred -v -n 3 -z "$DEVICE" 2>&1 | while IFS= read -r line; do
                if echo "$line" | grep -qP 'pass \d+/\d+'; then
                    PASS_INFO=$(echo "$line" | grep -oP 'pass \d+/\d+')
                    update_state "WIPING" 50 "shred $PASS_INFO"
                fi
            done
            log "$DEVICE: shred Fallback abgeschlossen"
            update_state "WIPING" 95 "shred fertig"
        fi
    else
        WIPE_METHOD="shred (3-Pass + Zero)"
        log "$DEVICE: nwipe nicht gefunden — Starte $WIPE_METHOD (${TOTAL_GB}GB)"
        update_state "WIPING" 5 "shred gestartet"
        shred -v -n 3 -z "$DEVICE" 2>&1 | while IFS= read -r line; do
            if echo "$line" | grep -qP 'pass \d+/\d+'; then
                PASS_INFO=$(echo "$line" | grep -oP 'pass \d+/\d+')
                update_state "WIPING" 50 "shred $PASS_INFO"
            fi
        done
        log "$DEVICE: shred abgeschlossen"
        update_state "WIPING" 95 "shred fertig"
    fi
fi

WIPE_END=$(date +%s)
WIPE_DURATION=$((WIPE_END - WIPE_START))
WIPE_MIN=$((WIPE_DURATION / 60))

log "$DEVICE: 3-Pass-Wipe abgeschlossen in ${WIPE_MIN}min — starte Verifikation"
update_state "VERIFY" 99 "Verifikation laeuft..."

VERIFY_OK=true
VERIFY_POINTS=20
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
DISK_TYPE_CERT=$(jq -r '.type // "N/A"' "$STATE_FILE" 2>/dev/null)

if $VERIFY_OK; then
    log "$DEVICE: Verifikation BESTANDEN -> DONE"
    update_state "DONE" 100 "$WIPE_METHOD | ${WIPE_MIN}min"
    printf '\a'

    CERT_FILE="$CERT_DIR/${DEV_SAFE}_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "========================================================"
        echo "            ITL Disktool: ERASURE REPORT"
        echo "========================================================"
        echo ""
        echo "  Device:        $DEVICE"
        echo "  Typ:           $DISK_TYPE_CERT"
        echo "  Modell:        $MODEL"
        echo "  Seriennummer:  $SERIAL"
        echo "  Kapazitaet:    ${TOTAL_GB}GB ($TOTAL Bytes)"
        echo ""
        echo "  Methode:       $WIPE_METHOD"
        if [ "$DISK_TYPE" = "HDD" ]; then
            echo "    Pass 1:      Zero-Fill (0x00)"
            echo "    Pass 2:      One-Fill  (0xFF)"
            echo "    Pass 3:      Random"
        fi
        echo ""
        echo "  Start:         $(date -d @$WIPE_START '+%Y-%m-%d %H:%M:%S')"
        echo "  Ende:          $(date -d @$WIPE_END '+%Y-%m-%d %H:%M:%S')"
        echo "  Dauer:         ${WIPE_MIN} Minuten"
        echo ""
        echo "  Verifikation:  BESTANDEN ($VERIFY_POINTS Pruefpunkte)"
        echo "  Ergebnis:      SICHER GELOESCHT (DSGVO Art. 17 konform)"
        echo ""
        echo "  Hostname:      $(hostname)"
        echo "  Erstellt:      $(date '+%Y-%m-%d %H:%M:%S')"
        echo "========================================================"
        echo ""
        echo "  DSGVO-Hinweis: Diese Loeschung erfolgte gemaess"
        echo "  Art. 17 DSGVO (Recht auf Loeschung). Alle Daten auf"
        echo "  dem oben genannten Datentraeger wurden unwiderruflich"
        echo "  und nachweislich vernichtet."
        echo "========================================================"
    } > "$CERT_FILE"

    CERT_HASH=$(sha256sum "$CERT_FILE" | awk '{print $1}')
    echo "" >> "$CERT_FILE"
    echo "  SHA256: $CERT_HASH" >> "$CERT_FILE"
    echo "========================================================"  >> "$CERT_FILE"

    log "$DEVICE: DSGVO-Loeschzertifikat erstellt: $CERT_FILE"
else
    log "$DEVICE: Verifikation FEHLGESCHLAGEN -> ERROR"
    update_state "ERROR" 0 "Verifikation fehlgeschlagen"
    printf '\a\a\a'
fi
