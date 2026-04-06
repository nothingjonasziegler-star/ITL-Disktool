#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

FALLBACK_IP="192.168.1.200"
FALLBACK_PREFIX="24"

if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

get_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v '^lo$'
}

get_current_ip() {
    ip -4 addr show scope global 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1
}

interfaces=$(get_interfaces)

for iface in $interfaces; do
    ip link set "$iface" up 2>/dev/null || true
    dhclient -v "$iface" 2>/dev/null || true
done

sleep 2

IP=$(get_current_ip)

if [ -z "$IP" ]; then
    for iface in $interfaces; do
        ip addr flush dev "$iface" 2>/dev/null || true
        ip addr add "${FALLBACK_IP}/${FALLBACK_PREFIX}" dev "$iface" 2>/dev/null || true
        ip link set "$iface" up 2>/dev/null || true
        break
    done
    IP="$FALLBACK_IP"
fi

SEP="===================================================="
echo ""
echo "$SEP"
echo "  DiskToolITL 1.0"
echo "  IP: ${IP}"
echo "$SEP"
echo ""

echo "$IP"
