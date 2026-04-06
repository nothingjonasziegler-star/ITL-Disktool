#!/bin/bash
set -uo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

POLL_INTERVAL=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIPE_DB="/tmp/wipe_db"
LOG_DIR="$SCRIPT_DIR/logs"
LOG="$LOG_DIR/disktoolitl.log"
mkdir -p "$LOG_DIR"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; logger -t disktoolitl "$1" 2>/dev/null || true; }

declare -A known_disks

get_boot_disk() {
    findmnt -n -o SOURCE / 2>/dev/null \
        | grep -oP '/dev/(?:sd[a-z]|hd[a-z]|vd[a-z]|nvme\d+n\d+)' \
        | head -1
}

get_all_disks() {
    lsblk -dno NAME,TYPE 2>/dev/null \
        | awk '$2=="disk" {print "/dev/" $1}'
}

process_disk() {
    local device="$1"
    log "Starte Verarbeitung: $device (Typ: $(lsblk -dno TRAN "$device" 2>/dev/null || echo 'unbekannt'))"
    bash "$SCRIPT_DIR/smart_check.sh" "$device"
    bash "$SCRIPT_DIR/uploader.sh"    "$device"
    bash "$SCRIPT_DIR/wipe_disk.sh"   "$device"
}

BOOT_DISK=$(get_boot_disk)
log "Boot-Disk erkannt und ausgeschlossen: $BOOT_DISK"

while IFS= read -r disk; do
    if [ "$disk" != "$BOOT_DISK" ]; then
        known_disks[$disk]=1
        log "Vorhandene Disk beim Start uebersprungen: $disk"
    fi
done < <(get_all_disks)

log "Ueberwachung gestartet -- nur NEU angeschlossene Disks werden verarbeitet"

if command -v udevadm &>/dev/null; then
    log "udevadm monitor aktiv — warte auf Disk-Events"
    udevadm monitor --kernel --subsystem-match=block 2>/dev/null | while IFS= read -r line; do
        if echo "$line" | grep -qP 'add.*disk'; then
            DEVPATH=$(echo "$line" | grep -oP '/dev/\S+' | head -1)
            [ -z "$DEVPATH" ] && continue

            DEVNAME=$(echo "$line" | grep -oP '(sd[a-z]+|nvme\d+n\d+|vd[a-z]+)' | head -1)
            [ -z "$DEVNAME" ] && continue
            disk="/dev/$DEVNAME"

            [ -b "$disk" ] || continue
            lsblk -dno TYPE "$disk" 2>/dev/null | grep -q "^disk$" || continue

            if [ -z "${known_disks[$disk]+x}" ] && [ "$disk" != "$BOOT_DISK" ]; then
                known_disks[$disk]=1
                log "udevadm: Neue Disk erkannt: $disk"
                process_disk "$disk" &
            fi

        elif echo "$line" | grep -qP 'remove.*disk'; then
            DEVNAME=$(echo "$line" | grep -oP '(sd[a-z]+|nvme\d+n\d+|vd[a-z]+)' | head -1)
            [ -z "$DEVNAME" ] && continue
            disk="/dev/$DEVNAME"
            DEV_SAFE=$(basename "$disk")
            STATE_FILE="$WIPE_DB/${DEV_SAFE}_state.json"

            if [ -f "$STATE_FILE" ]; then
                CURRENT_STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null)
                if [ "$CURRENT_STATUS" = "WIPING" ] || [ "$CURRENT_STATUS" = "VERIFY" ] || [ "$CURRENT_STATUS" = "SMART" ]; then
                    TMP=$(jq --arg s "ERROR" --argjson p 0 --arg e "Disk abgezogen" \
                          '.status = $s | .progress = $p | .extra = $e' "$STATE_FILE")
                    echo "$TMP" > "$STATE_FILE"
                    log "udevadm: Disk entfernt waehrend $CURRENT_STATUS: $disk -> ERROR"
                fi
            fi
            unset "known_disks[$disk]" 2>/dev/null || true
        fi
    done
else
    log "udevadm nicht verfuegbar — Fallback auf Polling (${POLL_INTERVAL}s)"
    while true; do
        while IFS= read -r disk; do
            if [ -z "${known_disks[$disk]+x}" ] && [ "$disk" != "$BOOT_DISK" ]; then
                known_disks[$disk]=1
                log "Neue Disk erkannt: $disk"
                process_disk "$disk" &
            fi
        done < <(get_all_disks)
        sleep "$POLL_INTERVAL"
    done
fi
