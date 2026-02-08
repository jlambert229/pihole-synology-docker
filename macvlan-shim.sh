#!/bin/bash
# macvlan-shim.sh — Enable Synology host ↔ Pi-hole container communication
#
# WHY: macvlan gives Pi-hole its own LAN IP, but by design the host
#      cannot talk to macvlan containers directly. This script creates a
#      "shim" interface that bridges that gap — allowing the Synology
#      itself to use Pi-hole as its DNS server.
#
# Supports start/stop arguments for use as an rc.d boot script.
# Installed to /usr/local/etc/rc.d/ by deploy.sh — runs automatically at boot.
#
# Usage:
#   sudo bash macvlan-shim.sh          # start (default)
#   sudo bash macvlan-shim.sh start    # explicit start
#   sudo bash macvlan-shim.sh stop     # tear down shim

set -euo pipefail

# ═════════════════════════════════════════════════════════════════════
# CONFIGURATION (must match docker-compose.yml)
# ═════════════════════════════════════════════════════════════════════
PARENT_IF="eth0"                 # Your NAS's primary network interface
SHIM_IF="macvlan-shim"
SHIM_IP="192.168.1.200"          # Unused LAN IP for the shim (must not conflict!)
PIHOLE_IP="192.168.1.53"         # Pi-hole's macvlan IP (must match docker-compose.yml)
# ═════════════════════════════════════════════════════════════════════

start() {
    echo "Creating macvlan shim: ${SHIM_IF} (${SHIM_IP}) → ${PIHOLE_IP}"

    # Remove existing shim if present (idempotent)
    ip link del "$SHIM_IF" 2>/dev/null || true

    # Create macvlan shim on the same parent as the Pi-hole container
    ip link add "$SHIM_IF" link "$PARENT_IF" type macvlan mode bridge
    ip addr add "${SHIM_IP}/32" dev "$SHIM_IF"
    ip link set "$SHIM_IF" up

    # Route Pi-hole traffic through the shim
    ip route add "${PIHOLE_IP}/32" dev "$SHIM_IF"

    echo "Done. Synology can now reach Pi-hole at ${PIHOLE_IP}"
}

stop() {
    echo "Removing macvlan shim: ${SHIM_IF}"
    ip link del "$SHIM_IF" 2>/dev/null || true
    echo "Done."
}

case "${1:-start}" in
    start) start ;;
    stop)  stop  ;;
    *)     echo "Usage: $0 {start|stop}"; exit 1 ;;
esac
