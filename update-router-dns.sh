#!/usr/bin/env bash
# update-router-dns.sh — Point router DHCP at Pi-hole (Example for EdgeRouter/UniFi)
#
# This is a TEMPLATE script for EdgeRouter/UniFi/VyOS routers.
# Adapt the configuration commands for your specific router platform.
#
# Updates DHCP dns-server settings so all clients receive Pi-hole as their DNS.
#
# Run AFTER Pi-hole is verified working (./verify.sh).
#
# Usage: ./update-router-dns.sh

set -euo pipefail

# ═════════════════════════════════════════════════════════════════════
# CONFIGURATION — Edit these to match your setup
# ═════════════════════════════════════════════════════════════════════
ROUTER_USER="ubnt"               # SSH username on router (e.g., ubnt, admin)
ROUTER_IP="192.168.1.1"          # Your router's IP address
ROUTER_HOST="${ROUTER_USER}@${ROUTER_IP}"
PIHOLE_IP="192.168.1.53"         # Pi-hole's IP (must match docker-compose.yml)
# ═════════════════════════════════════════════════════════════════════

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; exit 1; }
info() { printf "  → %s\n" "$*"; }
step() { printf "\n\033[1m[%s]\033[0m %s\n" "$1" "$2"; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Router DHCP → Pi-hole             ║"
echo "╚══════════════════════════════════════╝"

# ─────────────────────────────────────────────
step "1/4" "Preflight"
# ─────────────────────────────────────────────
info "Testing SSH to ${ROUTER_HOST}..."
ssh -o ConnectTimeout=5 -o BatchMode=yes "${ROUTER_HOST}" "true" 2>/dev/null \
    || fail "Cannot SSH to ${ROUTER_HOST}. Check key auth and connectivity."
ok "SSH connection"

info "Testing Pi-hole DNS before cutting over..."
if dig +short +timeout=5 +tries=1 @"${PIHOLE_IP}" google.com >/dev/null 2>&1; then
    ok "Pi-hole is resolving queries at ${PIHOLE_IP}"
else
    fail "Pi-hole is NOT responding at ${PIHOLE_IP}. Run ./verify.sh first."
fi

# ─────────────────────────────────────────────
step "2/4" "Current DHCP DNS configuration"
# ─────────────────────────────────────────────
echo ""
echo "  ⚠️  This script is a TEMPLATE for EdgeRouter/UniFi/VyOS."
echo "  Adapt the commands below for your router platform."
echo ""
info "Example for EdgeRouter (VyOS-based):"
echo ""
echo "    ssh ${ROUTER_HOST} \"grep 'dns-server' /config/config.boot\""
echo ""

# ─────────────────────────────────────────────
step "3/4" "Manual configuration steps"
# ─────────────────────────────────────────────
echo ""
echo "  Update your router's DHCP configuration to advertise Pi-hole:"
echo ""
echo "  1. Log into your router (web UI or CLI)"
echo "  2. Find DHCP server settings"
echo "  3. Change DNS server from router IP to: ${PIHOLE_IP}"
echo "  4. Commit/save changes"
echo ""
echo "  Example EdgeRouter CLI commands:"
echo ""
echo "    configure"
echo "    set service dhcp-server shared-network-name LAN subnet 192.168.1.0/24 dns-server ${PIHOLE_IP}"
echo "    commit"
echo "    save"
echo "    exit"
echo ""

# ─────────────────────────────────────────────
step "4/4" "Force DHCP renewal on clients"
# ─────────────────────────────────────────────
echo ""
echo "  Existing DHCP clients keep their old DNS until lease renewal (24h)."
echo "  Force renewal now:"
echo ""
echo "    Linux:   sudo dhclient -r && sudo dhclient"
echo "    macOS:   sudo ipconfig set en0 DHCP"
echo "    Windows: ipconfig /release && ipconfig /renew"
echo ""
echo "════════════════════════════════════════"
echo "  Review the steps above and update your router manually."
echo "  For automated router updates, adapt this script for your platform."
echo "════════════════════════════════════════"
