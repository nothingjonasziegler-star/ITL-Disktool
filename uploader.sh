#!/bin/bash
set -uo pipefail

DEVICE="$1"
DEV_SAFE=$(basename "$DEVICE")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIPE_DB="/tmp/wipe_db"
LOG="$SCRIPT_DIR/logs/disktoolitl.log"
ENV_FILE="$SCRIPT_DIR/.env"
CERT_DIR="$SCRIPT_DIR/logs/certificates"
STATE_FILE="$WIPE_DB/${DEV_SAFE}_state.json"
MOUNT_POINT="/tmp/disktoolitl_share"

ts()  { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts)  $1" | tee -a "$LOG"; logger -t disktoolitl "$1" 2>/dev/null || true; }

if [ ! -f "$ENV_FILE" ]; then
    log "$DEVICE: Keine .env gefunden — Netzwerk-Upload uebersprungen"
    exit 0
fi

set -a
source "$ENV_FILE"
set +a

if [ -z "${SHARE_IP:-}" ] || [ -z "${SHARE_NAME:-}" ]; then
    log "$DEVICE: Kein Netzwerk-Share konfiguriert — Zertifikate nur lokal"
    exit 0
fi

STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null)
if [ "$STATUS" != "DONE" ]; then
    log "$DEVICE: Wipe nicht erfolgreich (Status: $STATUS) — kein Upload"
    exit 0
fi

CERT_FILES=$(find "$CERT_DIR" -name "${DEV_SAFE}_*.txt" -mmin -60 2>/dev/null)
if [ -z "$CERT_FILES" ]; then
    log "$DEVICE: Kein Zertifikat gefunden — Upload uebersprungen"
    exit 0
fi

mkdir -p "$MOUNT_POINT"

MOUNT_OPTS="vers=3.0,soft,timeo=10"
if [ -n "${SHARE_USER:-}" ] && [ -n "${SHARE_PASS:-}" ]; then
    MOUNT_OPTS="${MOUNT_OPTS},username=${SHARE_USER},password=${SHARE_PASS}"
else
    MOUNT_OPTS="${MOUNT_OPTS},guest"
fi

if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    log "$DEVICE: Mounte Netzwerk-Share //${SHARE_IP}/${SHARE_NAME}"
    if ! mount -t cifs "//${SHARE_IP}/${SHARE_NAME}" "$MOUNT_POINT" -o "$MOUNT_OPTS" 2>/dev/null; then
        log "$DEVICE: FEHLER: Netzwerk-Share nicht erreichbar — Zertifikate nur lokal gespeichert"
        rmdir "$MOUNT_POINT" 2>/dev/null || true
        exit 1
    fi
fi

HOST_DIR="$MOUNT_POINT/${SHARE_PATH:-$(hostname)}"
mkdir -p "$HOST_DIR" 2>/dev/null || true

COPY_OK=true
for cert in $CERT_FILES; do
    CERT_NAME=$(basename "$cert")
    if cp "$cert" "$HOST_DIR/$CERT_NAME" 2>/dev/null; then
        log "$DEVICE: Zertifikat kopiert -> //${SHARE_IP}/${SHARE_NAME}/${SHARE_PATH:-$(hostname)}/$CERT_NAME"
    else
        log "$DEVICE: FEHLER beim Kopieren von $CERT_NAME"
        COPY_OK=false
    fi
done

umount "$MOUNT_POINT" 2>/dev/null || true
rmdir "$MOUNT_POINT" 2>/dev/null || true

if $COPY_OK; then
    log "$DEVICE: Alle Zertifikate erfolgreich auf Netzwerk-Share gespeichert"
else
    log "$DEVICE: Einige Zertifikate konnten nicht kopiert werden — lokale Kopien vorhanden"
    exit 1
fi
