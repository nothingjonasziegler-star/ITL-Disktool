#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
WIPE_DB="/tmp/wipe_db"
LOG_FILE="$SCRIPT_DIR/logs/disktoolitl.log"

W=$'\033[1;37m'
DG=$'\033[0;90m'
CY=$'\033[0;36m'
GN=$'\033[0;32m'
YL=$'\033[1;33m'
R=$'\033[0;31m'
BR=$'\033[1;31m'
BD=$'\033[1m'
NC=$'\033[0m'
INV=$'\033[7m'

cleanup() {
    printf '\033[?25h'
    tput rmcup 2>/dev/null
    [ -t 0 ] && stty echo 2>/dev/null
    exit 0
}
trap cleanup INT TERM EXIT HUP

tput smcup 2>/dev/null
[ -t 0 ] && stty -echo 2>/dev/null
printf '\033[?25l'

get_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}'
}

format_uptime() {
    local sec=$1
    printf "%dd %02dh %02dm" $((sec/86400)) $(((sec%86400)/3600)) $(((sec%3600)/60))
}

put() {
    local row=$1 col=$2
    shift 2
    tput cup "$row" "$col"
    printf "$@"
}

clear_line() {
    local row=$1
    tput cup "$row" 0
    printf "%-${COLS}s" ""
}

draw() {
    COLS=$(tput cols)
    ROWS=$(tput lines)
    local row=0

    local IP
    IP=$(get_ip)
    IP=${IP:-N/A}
    local NOW
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    local UP_SEC
    UP_SEC=$(awk '{printf "%.0f", $1}' /proc/uptime 2>/dev/null)
    UP_SEC=${UP_SEC:-0}
    local UPTIME_STR
    UPTIME_STR=$(format_uptime "$UP_SEC")

    local TOTAL=0 ACTIVE=0 DONE_C=0 ERROR_C=0 SMART_C=0
    for sf in "$WIPE_DB"/*_state.json; do
        [ -f "$sf" ] || continue
        local S
        S=$(jq -r '.status // ""' "$sf" 2>/dev/null)
        TOTAL=$((TOTAL+1))
        case "$S" in
            WIPING|VERIFY) ACTIVE=$((ACTIVE+1)) ;;
            DONE)   DONE_C=$((DONE_C+1)) ;;
            ERROR)  ERROR_C=$((ERROR_C+1)) ;;
            SMART)  SMART_C=$((SMART_C+1)) ;;
        esac
    done

    clear_line $row
    put $row 2 "${BR}${BD} ___ _____ _       ____  _     _   _____           _${NC}"
    row=$((row+1))
    clear_line $row
    put $row 2 "${BR}${BD}|_ _|_   _| |     |  _ \\(_)___| | _|_   _|__   ___| |${NC}"
    row=$((row+1))
    clear_line $row
    put $row 2 "${BR}${BD} | |  | | | |     | | | | / __| |/ / | |/ _ \\ / _ \\ |${NC}"
    row=$((row+1))
    clear_line $row
    put $row 2 "${BR}${BD} | |  | | | |___  | |_| | \\__ \\   <  | | (_) | (_) | |${NC}"
    row=$((row+1))
    clear_line $row
    put $row 2 "${BR}${BD}|___| |_| |_____| |____/|_|___/_|\\_\\ |_|\\___/ \\___/|_|${NC}"
    row=$((row+1))

    clear_line $row
    row=$((row+1))

    clear_line $row
    put $row 2 "${W}${BD}Harddrive Cleaner v2.0${NC}  ${DG}|${NC}  ${CY}DOD 5220.22-M (3-Pass)${NC}"
    row=$((row+1))

    clear_line $row
    put $row 2 "${DG}IP: ${CY}${IP}${NC}  ${DG}|  Zeit: ${W}${NOW}${NC}  ${DG}|  Uptime: ${W}${UPTIME_STR}${NC}"
    row=$((row+1))

    clear_line $row
    row=$((row+1))

    clear_line $row
    local hline=""
    for (( i=0; i<COLS-2; i++ )); do hline+="-"; done
    put $row 1 "${DG}${hline}${NC}"
    row=$((row+1))

    local STAT_LINE=" Gesamt: ${W}${TOTAL}${NC}${DG} | Aktiv: ${YL}${ACTIVE}${NC}${DG} | Fertig: ${GN}${DONE_C}${NC}${DG} | Fehler: ${R}${ERROR_C}${NC}${DG} | SMART: ${CY}${SMART_C}${NC}"
    clear_line $row
    put $row 2 "${DG}${STAT_LINE}"
    row=$((row+1))

    clear_line $row
    put $row 1 "${DG}${hline}${NC}"
    row=$((row+1))

    clear_line $row
    row=$((row+1))

    clear_line $row
    put $row 2 "${DG}$(printf '%-12s %-5s %-18s %-14s %5s %5s  %-22s %s' 'DEVICE' 'TYP' 'MODELL' 'SERIAL' 'GB' 'TEMP' 'FORTSCHRITT' 'STATUS')${NC}"
    row=$((row+1))

    local disk_count=0
    for state_file in "$WIPE_DB"/*_state.json; do
        [ -f "$state_file" ] || continue
        [ $row -ge $((ROWS-10)) ] && break

        local DEV TYPE SIZE STATUS PROG MODEL SERIAL TEMP EXTRA SMART_RAW
        DEV=$(jq -r '.device // "?"' "$state_file" 2>/dev/null)
        TYPE=$(jq -r '.type // "?"' "$state_file" 2>/dev/null)
        SIZE=$(jq -r '.size_gb // 0' "$state_file" 2>/dev/null)
        STATUS=$(jq -r '.status // "?"' "$state_file" 2>/dev/null)
        PROG=$(jq -r '.progress // 0' "$state_file" 2>/dev/null)
        MODEL=$(jq -r '.model // ""' "$state_file" 2>/dev/null)
        SERIAL=$(jq -r '.serial // ""' "$state_file" 2>/dev/null)
        TEMP=$(jq -r '.temp // "null"' "$state_file" 2>/dev/null)
        EXTRA=$(jq -r '.extra // ""' "$state_file" 2>/dev/null)

        [ ${#MODEL} -gt 16 ] && MODEL="${MODEL:0:15}~"
        [ ${#SERIAL} -gt 12 ] && SERIAL="${SERIAL:0:11}~"

        local TEMP_STR="  --"
        [ "$TEMP" != "null" ] && [ -n "$TEMP" ] && TEMP_STR="${TEMP}C"

        local BAR_W=18 FILLED EMPTY BAR=""
        FILLED=$(awk "BEGIN{v=int($PROG*$BAR_W/100); if(v>$BAR_W) v=$BAR_W; print v}")
        EMPTY=$(( BAR_W - FILLED ))
        BAR="["
        for (( k=0; k<FILLED; k++ )); do BAR+="="; done
        if [ "$FILLED" -lt "$BAR_W" ] && [ "$FILLED" -gt 0 ]; then
            BAR+=">"
            EMPTY=$((EMPTY - 1))
        fi
        for (( k=0; k<EMPTY; k++ )); do BAR+=" "; done
        BAR+="]"

        local SC
        case "$STATUS" in
            SMART)  SC="$CY" ;;
            WIPING) SC="$YL" ;;
            DONE)   SC="$GN" ;;
            ERROR)  SC="$R"  ;;
            VERIFY) SC="$CY" ;;
            *)      SC="$DG" ;;
        esac

        local PROG_INT
        PROG_INT=$(awk "BEGIN{printf \"%.0f\", $PROG}")

        clear_line $row
        put $row 2 "${W}$(printf '%-12s' "$DEV")${NC} ${DG}$(printf '%-5s' "$TYPE")${NC} ${W}$(printf '%-18s' "$MODEL")${NC} ${DG}$(printf '%-14s' "$SERIAL")${NC} ${W}$(printf '%5.0f' "$SIZE")${NC} ${DG}$(printf '%5s' "$TEMP_STR")${NC}  ${SC}${BAR}${NC}${W}$(printf '%4s%%' "$PROG_INT")${NC} ${SC}${BD}$(printf '%-6s' "$STATUS")${NC}"

        row=$((row+1))

        if [ -n "$EXTRA" ]; then
            clear_line $row
            put $row 48 "${DG}${EXTRA}${NC}"
            row=$((row+1))
        fi

        disk_count=$((disk_count+1))
    done

    if [ $disk_count -eq 0 ]; then
        clear_line $row; row=$((row+1))
        clear_line $row
        put $row 2 "${DG}>>> Warte auf neue Datentraeger... Disk anschliessen um Wipe zu starten <<<${NC}"
        row=$((row+1))
    fi

    clear_line $row; row=$((row+1))

    clear_line $row
    put $row 1 "${DG}${hline}${NC}"
    row=$((row+1))

    clear_line $row
    put $row 2 "${W}${BD}LOG${NC}"
    row=$((row+1))

    clear_line $row
    put $row 1 "${DG}${hline}${NC}"
    row=$((row+1))

    local log_max=$(( ROWS - row - 2 ))
    [ $log_max -lt 2 ] && log_max=2
    [ $log_max -gt 15 ] && log_max=15
    local log_row=$row

    if [ -f "$LOG_FILE" ]; then
        while IFS= read -r line; do
            [ $log_row -ge $((ROWS-2)) ] && break
            clear_line $log_row
            local maxlen=$(( COLS - 5 ))
            put $log_row 3 "${DG}$(printf '%-.*s' "$maxlen" "$line")${NC}"
            log_row=$((log_row+1))
        done < <(tail -n "$log_max" "$LOG_FILE")
    else
        clear_line $log_row
        put $log_row 3 "${DG}Kein Log vorhanden${NC}"
        log_row=$((log_row+1))
    fi

    while [ $log_row -lt $((ROWS-1)) ]; do
        clear_line $log_row
        log_row=$((log_row+1))
    done

    tput cup $((ROWS-1)) 0
    printf "${INV}${DG} DiskToolITL 2.0  |  DOD 5220.22-M  |  Strg+C = Beenden %-*s${NC}" $(( COLS - 58 )) ""
}

clear
while true; do
    draw
    sleep 2
done
