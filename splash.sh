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
WR=$'\033[38;5;88m'
BD=$'\033[1m'
NC=$'\033[0m'
INV=$'\033[7m'
EL=$'\033[K'

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
clear

get_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}'
}

format_uptime() {
    local sec=$1
    printf "%dd %02dh %02dm" $((sec/86400)) $(((sec%86400)/3600)) $(((sec%3600)/60))
}

pad() {
    printf "%-${2}s" "$1"
}

draw() {
    local COLS ROWS
    COLS=$(tput cols)
    ROWS=$(tput lines)

    local IP NOW UP_SEC UPTIME_STR
    IP=$(get_ip)
    IP=${IP:-N/A}
    NOW=$(date '+%Y-%m-%d %H:%M:%S')
    UP_SEC=$(awk '{printf "%.0f", $1}' /proc/uptime 2>/dev/null)
    UP_SEC=${UP_SEC:-0}
    UPTIME_STR=$(format_uptime "$UP_SEC")

    local TOTAL=0 ACTIVE=0 DONE_C=0 ERROR_C=0 SMART_C=0
    for sf in "$WIPE_DB"/*_state.json; do
        [ -f "$sf" ] || continue
        local S
        S=$(jq -r '.status // ""' "$sf" 2>/dev/null)
        TOTAL=$((TOTAL+1))
        case "$S" in
            WIPING|VERIFY) ACTIVE=$((ACTIVE+1)) ;;
            DONE)          DONE_C=$((DONE_C+1)) ;;
            ERROR)         ERROR_C=$((ERROR_C+1)) ;;
            SMART)         SMART_C=$((SMART_C+1)) ;;
        esac
    done

    local hline=""
    for (( i=0; i<COLS-2; i++ )); do hline+="-"; done

    local BUF=""
    BUF+="\033[H"

    BUF+="  ${WR}${BD}█████████████████████████████████████${NC}${EL}\n"
    BUF+="  ${WR}${BD}█████████████████████████████████████${NC}${EL}\n"
    BUF+="  ${WR}${BD}            ████   ████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   ████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   ████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   ████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   ████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   ████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   ████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   █████████████████${NC}${EL}\n"
    BUF+="  ${WR}${BD}     ████   ████   █████████████████${NC}${EL}\n"
    BUF+="${EL}\n"
    BUF+="  ${W}${BD}Harddrive Cleaner v2.0${NC}  ${DG}|${NC}  ${CY}DOD 5220.22-M (3-Pass)${NC}${EL}\n"
    BUF+="  ${DG}IP: ${CY}${IP}${NC}  ${DG}|  Zeit: ${W}${NOW}${NC}  ${DG}|  Uptime: ${W}${UPTIME_STR}${NC}${EL}\n"
    BUF+="${EL}\n"
    BUF+=" ${DG}${hline}${NC}\n"
    BUF+="  ${DG}Gesamt: ${W}${TOTAL}${NC}${DG} | Aktiv: ${YL}${ACTIVE}${NC}${DG} | Fertig: ${GN}${DONE_C}${NC}${DG} | Fehler: ${R}${ERROR_C}${NC}${DG} | SMART: ${CY}${SMART_C}${NC}${EL}\n"
    BUF+=" ${DG}${hline}${NC}\n"
    BUF+="${EL}\n"

    local header
    header=$(printf '  %-12s %-5s %-18s %-14s %5s %5s  %-22s %s' 'DEVICE' 'TYP' 'MODELL' 'SERIAL' 'GB' 'TEMP' 'FORTSCHRITT' 'STATUS')
    BUF+="${DG}${header}${NC}${EL}\n"

    local row=22
    local disk_count=0
    for state_file in "$WIPE_DB"/*_state.json; do
        [ -f "$state_file" ] || continue
        [ $row -ge $((ROWS-10)) ] && break

        local DEV TYPE SIZE STATUS PROG MODEL SERIAL TEMP EXTRA
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

        BUF+="  ${W}$(printf '%-12s' "$DEV")${NC} ${DG}$(printf '%-5s' "$TYPE")${NC} ${W}$(printf '%-18s' "$MODEL")${NC} ${DG}$(printf '%-14s' "$SERIAL")${NC} ${W}$(printf '%5.0f' "$SIZE")${NC} ${DG}$(printf '%5s' "$TEMP_STR")${NC}  ${SC}${BAR}${NC}${W}$(printf '%4s%%' "$PROG_INT")${NC} ${SC}${BD}$(printf '%-6s' "$STATUS")${NC}${EL}\n"
        row=$((row+1))

        if [ -n "$EXTRA" ]; then
            BUF+="$(printf '%48s' '')${DG}${EXTRA}${NC}${EL}\n"
            row=$((row+1))
        fi

        disk_count=$((disk_count+1))
    done

    if [ $disk_count -eq 0 ]; then
        BUF+="${EL}\n"
        BUF+="  ${DG}>>> Warte auf neue Datentraeger... Disk anschliessen um Wipe zu starten <<<${NC}${EL}\n"
        row=$((row+2))
    fi

    BUF+="${EL}\n"
    BUF+=" ${DG}${hline}${NC}\n"
    BUF+="  ${W}${BD}LOG${NC}${EL}\n"
    BUF+=" ${DG}${hline}${NC}\n"
    row=$((row+4))

    local log_max=$(( ROWS - row - 3 ))
    [ $log_max -lt 2 ] && log_max=2
    [ $log_max -gt 15 ] && log_max=15

    if [ -f "$LOG_FILE" ]; then
        local maxlen=$(( COLS - 5 ))
        while IFS= read -r line; do
            BUF+="   ${DG}$(printf '%-.*s' "$maxlen" "$line")${NC}${EL}\n"
            row=$((row+1))
        done < <(tail -n "$log_max" "$LOG_FILE")
    else
        BUF+="   ${DG}Kein Log vorhanden${NC}${EL}\n"
        row=$((row+1))
    fi

    while [ $row -lt $((ROWS-1)) ]; do
        BUF+="${EL}\n"
        row=$((row+1))
    done

    BUF+="${INV}${DG} DiskToolITL 2.0  |  DOD 5220.22-M  |  Strg+C = Beenden $(printf '%-*s' $(( COLS - 58 )) '')${NC}"

    printf '%b' "$BUF"
}

while true; do
    draw
    sleep 2
done
