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

build_content() {
    local IP ROWS COLS
    IP=$(get_ip)
    ROWS=$(tput lines)
    COLS=$(tput cols)

    local c=""
    c+="\n"
    c+="  ITL Disktool - Harddrive cleaner tool\n"
    c+="  Version 1.0 | IP: ${IP}\n"
    c+="\n"
    c+="  ---------------------------------------------------------------\n"
    c+="  FESTPLATTEN STATUS\n"
    c+="  ---------------------------------------------------------------\n"
    c+="$(printf '  %-14s %-5s %7s %-6s %-24s %s' 'DEVICE' 'TYP' 'GROESSE' 'SMART' 'FORTSCHRITT' 'STATUS')\n"

    local disk_count=0
    for state_file in "$WIPE_DB"/*_state.json; do
        [ -f "$state_file" ] || continue

        local DEV TYPE SIZE STATUS PROG SMART_RAW
        DEV=$(jq -r '.device // "?"' "$state_file" 2>/dev/null)
        TYPE=$(jq -r '.type // "?"' "$state_file" 2>/dev/null)
        SIZE=$(jq -r '.size_gb // 0' "$state_file" 2>/dev/null)
        STATUS=$(jq -r '.status // "?"' "$state_file" 2>/dev/null)
        PROG=$(jq -r '.progress // 0' "$state_file" 2>/dev/null)
        SMART_RAW=$(jq -r '.smart_passed // "null"' "$state_file" 2>/dev/null)

        local BAR_W=20 FILLED EMPTY BAR=""
        FILLED=$(awk "BEGIN{printf \"%d\", $PROG*$BAR_W/100}")
        EMPTY=$(( BAR_W - FILLED ))
        BAR="["
        for (( k=0; k<FILLED; k++ )); do BAR+="#"; done
        for (( k=0; k<EMPTY; k++ )); do BAR+="-"; done
        BAR+="]"

        local SMART_STR="--"
        [ "$SMART_RAW" = "true" ] && SMART_STR="PASS"
        [ "$SMART_RAW" = "false" ] && SMART_STR="FAIL"

        c+="$(printf '  %-14s %-5s %5.0fGB %-6s %s %3.0f%% %-6s' "$DEV" "$TYPE" "$SIZE" "$SMART_STR" "$BAR" "$PROG" "$STATUS")\n"
        disk_count=$((disk_count+1))
    done

    if [ $disk_count -eq 0 ]; then
        c+="  Warte auf neue Datentraeger...\n"
    fi

    c+="\n"
    c+="  ---------------------------------------------------------------\n"
    c+="  LOG\n"
    c+="  ---------------------------------------------------------------\n"

    local log_max=$(( ROWS - disk_count - 18 ))
    [ $log_max -lt 3 ] && log_max=3
    [ $log_max -gt 20 ] && log_max=20

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
    ROWS=$(tput lines)
    COLS=$(tput cols)
    CONTENT=$(build_content)
    dialog --no-collapse \
           --title " DiskToolITL 1.0 | Strg+C zum Beenden " \
           --infobox "$CONTENT" "$((ROWS - 2))" "$((COLS - 2))"
    sleep 2
done
