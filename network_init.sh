#!/bin/bash
set -uo pipefail

FALLBACK_IP="192.168.1.200"
FALLBACK_PREFIX="24"

get_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | cut -d'@' -f1 | grep -v '^lo$'
}

get_current_ip() {
    ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1); exit}'
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
echo "  Web-GUI : http://${IP}:8080"
echo "$SEP"
echo ""

echo "$IP"
