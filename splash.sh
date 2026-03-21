#!/bin/bash
WIPE_DB="/tmp/wipe_db"
LOG_FILE="/var/log/disktoolitl/disktoolitl.log"

R=$'\033[0;31m'
BR=$'\033[1;31m'
W=$'\033[1;37m'
DG=$'\033[0;90m'
CY=$'\033[0;36m'
GN=$'\033[0;32m'
YL=$'\033[1;33m'
NC=$'\033[0m'
BD=$'\033[1m'
BG41=$'\033[41m'

BLINK=0

cleanup() {
    printf '\033[?25h'
    tput rmcup
    [ -t 0 ] && stty echo 2>/dev/null
    exit 0
}
trap cleanup INT TERM EXIT HUP

tput smcup
[ -t 0 ] && stty -echo 2>/dev/null
printf '\033[?25l'

get_ip() {
    local ip
    ip=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}')
    echo "${ip:-N/A}"
}

hline() {
    local COLS; COLS=$(tput cols)
    printf "${DG}"; printf '─%.0s' $(seq 1 "$COLS"); printf "${NC}"
}

draw() {
    local COLS ROWS
    COLS=$(tput cols)
    ROWS=$(tput lines)
    local row=0 k

    # ── top margin ────────────────────────────────────────
    tput cup 0 0; printf "%-${COLS}s" ""
    tput cup 1 0; printf "%-${COLS}s" ""
    row=2

    # ── LOGO ──────────────────────────────────────────────
    # Logo is 41 chars wide; center it, label starts 4 chars to the right
    local LW=41
    local LC=$(( (COLS - LW) / 2 ))
    [[ $LC -lt 1 ]] && LC=1
    local TX=$(( LC + LW + 4 ))

    local -a LOGO_LINES=(
 
        "                                       "
        "█████████████████████████████████████  "
        "█████████████████████████████████████  "
        "             ████   ████               "
        "      ████   ████   ████               "
        "      ████   ████   ████               "
        "      ████   ████   ████               "
        "      ████   ████   ████               "
        "      ████   ████   ████               "
        "      ████   ████   ████               "
        "      ████   ████   █████████████████  "
        "      ████   ████   █████████████████  "
        "                                       "
    )

    local -a LABEL_LINES=(
        ""
        ""
        "${BR}${BD}ITL Disktool${NC}"
        "${DG}Harddrive cleaner tool${NC}"
        "${DG}based on Debian${NC}"
        "${DG}Version 1.0${NC}"
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
        ""
    )

    for i in "${!LOGO_LINES[@]}"; do
        tput cup $row 0; printf "%-${COLS}s" ""
        tput cup $row $LC
        printf "${R}${BD}%s${NC}" "${LOGO_LINES[$i]}"
        if [[ -n "${LABEL_LINES[$i]}" ]]; then
            tput cup $row $TX
            printf "%b" "${LABEL_LINES[$i]}"
        fi
        row=$((row+1))
    done

    tput cup $row 0; printf "%-${COLS}s" ""
    row=$((row+1))

    # ── separator ─────────────────────────────────────────
    tput cup $row 0; hline
    row=$((row+1))

    # ── STATUS BAR ────────────────────────────────────────
    local IP; IP=$(get_ip)
    local DOT
    [[ $BLINK -eq 1 ]] && DOT="${R}●${NC}" || DOT="${DG}●${NC}"

    tput cup $row 0; printf "%-${COLS}s" ""; tput cup $row 2
    printf " ${DOT} ${BD}SYSTEM AKTIV${NC}     ${DG}Web-GUI:${NC} ${CY}http://${IP}:8080${NC}"
    row=$((row+1))

    tput cup $row 0; printf "%-${COLS}s" ""
    row=$((row+1))

    # ── separator ─────────────────────────────────────────
    tput cup $row 0; hline
    row=$((row+1))

    # ── DISK TABLE ────────────────────────────────────────
    tput cup $row 0; printf "%-${COLS}s" ""; tput cup $row 2
    printf "${BD}${W}▸ FESTPLATTEN STATUS${NC}"
    row=$((row+1))

    tput cup $row 0; printf "%-${COLS}s" ""; tput cup $row 4
    printf "${DG}%-14s  %-5s  %6s  %-6s  %-22s  %s${NC}" \
        "DEVICE" "TYP" "GRÖßE" "SMART" "FORTSCHRITT" "STATUS"
    row=$((row+1))

    local disk_count=0
    for state_file in "$WIPE_DB"/*_state.json; do
        [[ -f "$state_file" ]] || continue
        [[ $row -ge $((ROWS-7)) ]] && break

        local DEV TYPE SIZE STATUS PROG SMART_RAW
        DEV=$(jq -r      '.device       // "?"'    "$state_file" 2>/dev/null)
        TYPE=$(jq -r     '.type         // "?"'    "$state_file" 2>/dev/null)
        SIZE=$(jq -r     '.size_gb      // 0'      "$state_file" 2>/dev/null)
        STATUS=$(jq -r   '.status       // "?"'    "$state_file" 2>/dev/null)
        PROG=$(jq -r     '.progress     // 0'      "$state_file" 2>/dev/null)
        SMART_RAW=$(jq -r '.smart_passed // "null"' "$state_file" 2>/dev/null)

        local BAR_W=22 FILLED EMPTY BAR=""
        FILLED=$(awk "BEGIN{printf \"%d\", $PROG*$BAR_W/100}")
        EMPTY=$(( BAR_W - FILLED ))
        for (( k=0; k<FILLED; k++ )); do BAR+="█"; done
        for (( k=0; k<EMPTY;  k++ )); do BAR+="░"; done

        local SC
        case "$STATUS" in
            SMART)  SC="$CY" ;;
            WIPING) SC="$YL" ;;
            DONE)   SC="$GN" ;;
            ERROR)  SC="$R"  ;;
            *)      SC="$DG" ;;
        esac

        local SMART_STR="${DG} –${NC}"
        [[ "$SMART_RAW" == "true"  ]] && SMART_STR="${GN}PASS${NC}"
        [[ "$SMART_RAW" == "false" ]] && SMART_STR="${R}FAIL${NC}"

        tput cup $row 0; printf "%-${COLS}s" ""; tput cup $row 4
        printf "${W}%-14s${NC}  ${DG}%-5s${NC}  ${W}%5.0fGB${NC}  ${SMART_STR}    ${DG}[${NC}${SC}%s${NC}${DG}]${NC}  ${SC}%-6s${NC} ${DG}%.0f%%${NC}" \
            "$DEV" "$TYPE" "$SIZE" "$BAR" "$STATUS" "$PROG"

        row=$((row+1))
        disk_count=$((disk_count+1))
    done

    if [[ $disk_count -eq 0 ]]; then
        tput cup $row 0; printf "%-${COLS}s" ""; tput cup $row 4
        printf "${DG}Warte auf Datenträger...${NC}"
        row=$((row+1))
    fi

    tput cup $row 0; printf "%-${COLS}s" ""
    row=$((row+1))

    # ── separator ─────────────────────────────────────────
    tput cup $row 0; hline
    row=$((row+1))

    # ── LOG ───────────────────────────────────────────────
    tput cup $row 0; printf "%-${COLS}s" ""; tput cup $row 2
    printf "${BD}${W}▸ LOG${NC}"
    row=$((row+1))

    local log_avail=$(( ROWS - row - 1 ))
    [[ $log_avail -lt 1 ]] && log_avail=1
    local log_row=$row

    if [[ -f "$LOG_FILE" ]]; then
        while IFS= read -r line; do
            [[ $log_row -ge $((ROWS-1)) ]] && break
            local maxlen=$(( COLS - 5 ))
            tput cup $log_row 0; printf "%-${COLS}s" ""; tput cup $log_row 4
            printf "${DG}%-${maxlen}.${maxlen}s${NC}" "$line"
            log_row=$((log_row+1))
        done < <(tail -n "$log_avail" "$LOG_FILE")
    else
        tput cup $log_row 0; printf "%-${COLS}s" ""; tput cup $log_row 4
        printf "${DG}Kein Log vorhanden${NC}"
        log_row=$((log_row+1))
    fi

    while [[ $log_row -lt $((ROWS-1)) ]]; do
        tput cup $log_row 0; printf "%-${COLS}s" ""
        log_row=$((log_row+1))
    done

    # ── BOTTOM BAR ────────────────────────────────────────
    tput cup $((ROWS-1)) 0
    local footer="  DiskToolITL 1.0  │  Strg+C zum Beenden"
    printf "${DG}%-${COLS}s${NC}" "$footer"
}

# ── MAIN ──────────────────────────────────────────────────
while true; do
    draw
    sleep 1
    BLINK=$(( 1 - BLINK ))
done
