#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
WIPE_DB="/tmp/wipe_db"
LOG_FILE="$SCRIPT_DIR/logs/disktoolitl.log"

get_ip() {
    local ip
    ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
    echo "${ip:-N/A}"
}

format_uptime() {
    local sec=$1
    printf "%dd %02dh %02dm" $((sec/86400)) $(((sec%86400)/3600)) $(((sec%3600)/60))
}

build_content() {
    local IP ROWS COLS
    IP=$(get_ip)
    ROWS=$(tput lines 2>/dev/null || echo 24)
    COLS=$(tput cols 2>/dev/null || echo 80)
    local UP_SEC=$(cat /proc/uptime 2>/dev/null | awk '{printf "%.0f", $1}')
    UP_SEC=${UP_SEC:-0}
    local UPTIME_STR
    UPTIME_STR=$(format_uptime "$UP_SEC")
    local NOW
    NOW=$(date '+%Y-%m-%d %H:%M:%S')

    local TOTAL=0 ACTIVE=0 DONE_C=0 ERROR_C=0 SMART_C=0 VERIFY_C=0
    for sf in "$WIPE_DB"/*_state.json; do
        [ -f "$sf" ] || continue
        local S
        S=$(jq -r '.status // ""' "$sf" 2>/dev/null)
        TOTAL=$((TOTAL+1))
        case "$S" in
            WIPING) ACTIVE=$((ACTIVE+1)) ;;
            DONE)   DONE_C=$((DONE_C+1)) ;;
            ERROR)  ERROR_C=$((ERROR_C+1)) ;;
            SMART)  SMART_C=$((SMART_C+1)) ;;
            VERIFY) VERIFY_C=$((VERIFY_C+1)) ;;
        esac
    done

    local c=""
    c+=" _____ _____ _       ____  _     _    _____           _\n"
    c+="|_   _|_   _| |     |  _ \\(_)   | |  |_   _|__   ___ | |\n"
    c+="  | |   | | | |     | | | |_ ___| | __ | |/ _ \\ / _ \\| |\n"
    c+="  | |   | | | |___  | |_| | |__ | |/ / | | (_) | (_) | |\n"
    c+="  |_|   |_| |_____| |____/|_|___||___/  |_|\\___/ \\___/|_|\n"
    c+="\n"
    c+="  Harddrive Cleaner Tool v2.0 | DOD 5220.22-M (3-Pass)\n"
    c+="  $(printf '%-38s' "IP: ${IP}") Uptime: ${UPTIME_STR}\n"
    c+="  $(printf '%-38s' "Zeit: ${NOW}")\n"
    c+="\n"

    local SEP
    SEP=$(printf '%*s' "$((COLS - 6))" '' | tr ' ' '-')
    c+="  $SEP\n"
    c+="  STATISTIK:  Gesamt: $TOTAL | Aktiv: $ACTIVE | Fertig: $DONE_C | Fehler: $ERROR_C | SMART: $SMART_C\n"
    c+="  $SEP\n"
    c+="\n"
    c+="$(printf '  %-12s %-5s %-20s %-16s %5s %5s %-24s %s' 'DEVICE' 'TYP' 'MODELL' 'SERIAL' 'GB' 'TEMP' 'FORTSCHRITT' 'STATUS')\n"
    c+="  $SEP\n"

    local disk_count=0
    for state_file in "$WIPE_DB"/*_state.json; do
        [ -f "$state_file" ] || continue

        local DEV TYPE SIZE STATUS PROG SMART_RAW MODEL SERIAL TEMP EXTRA
        DEV=$(jq -r '.device // "?"' "$state_file" 2>/dev/null)
        TYPE=$(jq -r '.type // "?"' "$state_file" 2>/dev/null)
        SIZE=$(jq -r '.size_gb // 0' "$state_file" 2>/dev/null)
        STATUS=$(jq -r '.status // "?"' "$state_file" 2>/dev/null)
        PROG=$(jq -r '.progress // 0' "$state_file" 2>/dev/null)
        SMART_RAW=$(jq -r '.smart_passed // "null"' "$state_file" 2>/dev/null)
        MODEL=$(jq -r '.model // ""' "$state_file" 2>/dev/null)
        SERIAL=$(jq -r '.serial // ""' "$state_file" 2>/dev/null)
        TEMP=$(jq -r '.temp // "null"' "$state_file" 2>/dev/null)
        EXTRA=$(jq -r '.extra // ""' "$state_file" 2>/dev/null)

        [ ${#MODEL} -gt 18 ] && MODEL="${MODEL:0:17}~"
        [ ${#SERIAL} -gt 14 ] && SERIAL="${SERIAL:0:13}~"

        local TEMP_STR="--"
        [ "$TEMP" != "null" ] && [ -n "$TEMP" ] && TEMP_STR="${TEMP}C"

        local BAR_W=20 FILLED EMPTY BAR=""
        FILLED=$(awk "BEGIN{printf \"%d\", $PROG*$BAR_W/100}")
        EMPTY=$(( BAR_W - FILLED ))
        BAR="["
        for (( k=0; k<FILLED; k++ )); do BAR+="="; done
        if [ "$FILLED" -lt "$BAR_W" ] && [ "$FILLED" -gt 0 ]; then
            BAR+=">"
            EMPTY=$((EMPTY - 1))
        fi
        for (( k=0; k<EMPTY; k++ )); do BAR+=" "; done
        BAR+="]"

        local STATUS_FULL="$STATUS"
        if [ -n "$EXTRA" ]; then
            STATUS_FULL="$STATUS $EXTRA"
        fi

        c+="$(printf '  %-12s %-5s %-20s %-16s %5.0f %5s %s%4.0f%% %s' "$DEV" "$TYPE" "$MODEL" "$SERIAL" "$SIZE" "$TEMP_STR" "$BAR" "$PROG" "$STATUS_FULL")\n"
        disk_count=$((disk_count+1))
    done

    if [ $disk_count -eq 0 ]; then
        c+="\n"
        c+="  >>> Warte auf neue Datentraeger...  <<<\n"
        c+="  >>> Disk anschliessen um Wipe zu starten <<<\n"
    fi

    c+="\n"
    c+="  $SEP\n"
    c+="  LOG (letzte Eintraege)\n"
    c+="  $SEP\n"

    local log_max=$(( ROWS - disk_count - 24 ))
    [ $log_max -lt 3 ] && log_max=3
    [ $log_max -gt 15 ] && log_max=15

    if [ -f "$LOG_FILE" ]; then
        while IFS= read -r line; do
            c+="  $line\n"
        done < <(tail -n "$log_max" "$LOG_FILE")
    else
        c+="  Kein Log vorhanden\n"
    fi

    echo -e "$c"
}

trap "clear; exit 0" INT TERM EXIT HUP

while true; do
    ROWS=$(tput lines 2>/dev/null || echo 24)
    COLS=$(tput cols 2>/dev/null || echo 80)
    CONTENT=$(build_content)
    dialog --no-collapse \
           --title " DiskToolITL 2.0 | DOD 5220.22-M | Strg+C = Beenden " \
           --infobox "$CONTENT" "$((ROWS - 1))" "$((COLS - 1))"
    sleep 2
done
