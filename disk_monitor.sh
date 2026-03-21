#!/bin/bash
set -uo pipefail

POLL_INTERVAL=5
LOG="/var/log/disktoolitl/disktoolitl.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; }

declare -A known_disks

get_boot_disk() {
    findmnt -n -o SOURCE / 2>/dev/null \
        | grep -oP '/dev/(?:sd[a-z]|hd[a-z]|vd[a-z]|nvme\d+n\d+)' \
        | head -1
}

get_all_disks() {
    grep -E '^\s+[0-9]+ +[0-9]+ +[0-9]+ (sd[a-z]|hd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z])$' \
        /proc/partitions \
        | awk '{print "/dev/" $4}'
}

process_disk() {
    local device="$1"
    bash "$SCRIPT_DIR/smart_check.sh" "$device"
    bash "$SCRIPT_DIR/uploader.sh"    "$device"
    bash "$SCRIPT_DIR/wipe_disk.sh"   "$device"
}

BOOT_DISK=$(get_boot_disk)
log "Boot-Disk erkannt und ausgeschlossen: $BOOT_DISK"

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
