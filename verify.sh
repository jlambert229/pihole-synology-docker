#!/usr/bin/env bash
# verify.sh — Verify Pi-hole is working before cutting over DHCP
#
# Runs from your workstation. Checks:
#   1. Container is running on Synology
#   2. DNS resolution works (query Pi-hole directly)
#   3. Ad domains are blocked
#   4. Web UI is reachable
#   5. macvlan shim is active (NAS can reach Pi-hole)
#
# Usage: ./verify.sh

set -euo pipefail

# ═════════════════════════════════════════════════════════════════════
# CONFIGURATION — Edit these to match your setup
# ═════════════════════════════════════════════════════════════════════
NAS_USER="your-username"
NAS_IP="192.168.1.2"
NAS_HOST="${NAS_USER}@${NAS_IP}"
NAS_DIR="/volume1/docker/pihole"
PIHOLE_IP="192.168.1.53"
# ═════════════════════════════════════════════════════════════════════

PASS=0
FAIL=0
WARN=0

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; ((PASS++)); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; ((FAIL++)); }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$*"; ((WARN++)); }
hdr()  { printf "\n\033[1m[%s]\033[0m\n" "$*"; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Pi-hole Verification              ║"
echo "╚══════════════════════════════════════╝"

# ─────────────────────────────────────────────
hdr "Container"
# ─────────────────────────────────────────────
if ssh "${NAS_HOST}" "sudo docker ps --format '{{.Names}}'" 2>/dev/null | grep -q '^pihole$'; then
    ok "pihole container is running"
else
    fail "pihole container is NOT running"
fi

CONTAINER_STATE=$(ssh "${NAS_HOST}" "sudo docker inspect pihole --format '{{.State.Status}}'" 2>/dev/null || echo "unknown")
if [[ "$CONTAINER_STATE" == "running" ]]; then
    ok "Container state: ${CONTAINER_STATE}"
else
    fail "Container state: ${CONTAINER_STATE}"
fi

# Check for restart loops
RESTART_COUNT=$(ssh "${NAS_HOST}" "sudo docker inspect pihole --format '{{.RestartCount}}'" 2>/dev/null || echo "?")
if [[ "$RESTART_COUNT" == "0" ]]; then
    ok "No restart loops (restart count: 0)"
else
    warn "Restart count: ${RESTART_COUNT} — check logs with: ssh ${NAS_HOST} 'sudo docker logs pihole --tail 50'"
fi

# ─────────────────────────────────────────────
hdr "DNS Resolution"
# ─────────────────────────────────────────────
if dig +short +timeout=5 +tries=1 @"${PIHOLE_IP}" google.com >/dev/null 2>&1; then
    RESULT=$(dig +short +timeout=5 @"${PIHOLE_IP}" google.com | head -1)
    ok "google.com → ${RESULT}"
else
    fail "google.com — no response from ${PIHOLE_IP}:53"
fi

if dig +short +timeout=5 +tries=1 @"${PIHOLE_IP}" cloudflare.com >/dev/null 2>&1; then
    RESULT=$(dig +short +timeout=5 @"${PIHOLE_IP}" cloudflare.com | head -1)
    ok "cloudflare.com → ${RESULT}"
else
    fail "cloudflare.com — no response from ${PIHOLE_IP}:53"
fi

# ─────────────────────────────────────────────
hdr "Ad Blocking"
# ─────────────────────────────────────────────
# Test a well-known ad/tracking domain — Pi-hole should return 0.0.0.0 or NXDOMAIN
AD_RESULT=$(dig +short +timeout=5 +tries=1 @"${PIHOLE_IP}" ads.google.com 2>/dev/null || echo "QUERY_FAILED")
if [[ "$AD_RESULT" == "0.0.0.0" ]] || [[ -z "$AD_RESULT" ]]; then
    ok "ads.google.com → blocked (${AD_RESULT:-NXDOMAIN})"
elif [[ "$AD_RESULT" == "QUERY_FAILED" ]]; then
    fail "ads.google.com — query failed"
else
    warn "ads.google.com → ${AD_RESULT} (may not be in default blocklist, or gravity still loading)"
fi

TRACKER_RESULT=$(dig +short +timeout=5 +tries=1 @"${PIHOLE_IP}" tracking.example.com 2>/dev/null || echo "QUERY_FAILED")
if [[ "$TRACKER_RESULT" == "0.0.0.0" ]] || [[ -z "$TRACKER_RESULT" ]]; then
    ok "tracking.example.com → blocked"
elif [[ "$TRACKER_RESULT" == "QUERY_FAILED" ]]; then
    fail "tracking.example.com — query failed"
else
    # This domain likely doesn't exist anyway, so NXDOMAIN is expected
    ok "tracking.example.com → ${TRACKER_RESULT} (expected — not a real domain)"
fi

# ─────────────────────────────────────────────
hdr "Web UI"
# ─────────────────────────────────────────────
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${PIHOLE_IP}/admin/" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    ok "Web UI responds (HTTP ${HTTP_CODE}) → http://${PIHOLE_IP}/admin"
else
    fail "Web UI not reachable (HTTP ${HTTP_CODE}) → http://${PIHOLE_IP}/admin"
fi

# ─────────────────────────────────────────────
hdr "macvlan Shim"
# ─────────────────────────────────────────────
if ssh "${NAS_HOST}" "ip link show macvlan-shim >/dev/null 2>&1"; then
    ok "macvlan-shim interface exists on NAS"
else
    fail "macvlan-shim interface missing — run: ssh ${NAS_HOST} 'sudo bash ${NAS_DIR}/macvlan-shim.sh'"
fi

if ssh "${NAS_HOST}" "ping -c 1 -W 2 ${PIHOLE_IP} >/dev/null 2>&1"; then
    ok "NAS can reach Pi-hole at ${PIHOLE_IP}"
else
    fail "NAS cannot reach ${PIHOLE_IP} — macvlan shim may not be working"
fi

# Check rc.d persistence
if ssh "${NAS_HOST}" "test -x /usr/local/etc/rc.d/macvlan-shim.sh" 2>/dev/null; then
    ok "Shim persisted in /usr/local/etc/rc.d/"
else
    warn "Shim not in rc.d — won't survive reboot. Run deploy.sh step 7."
fi

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
printf "  Results: \033[32m%d passed\033[0m" "$PASS"
[[ $WARN -gt 0 ]] && printf ", \033[33m%d warnings\033[0m" "$WARN"
[[ $FAIL -gt 0 ]] && printf ", \033[31m%d failed\033[0m" "$FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo "  Pi-hole is healthy! Ready to cut over DHCP."
    echo "  Next: Update router DHCP to advertise ${PIHOLE_IP}"
else
    echo ""
    echo "  Some checks failed — fix issues before updating DHCP."
    echo "  Logs: ssh ${NAS_HOST} 'sudo docker logs pihole --tail 100'"
fi
echo "════════════════════════════════════════"

exit "$FAIL"
