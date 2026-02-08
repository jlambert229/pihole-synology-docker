#!/usr/bin/env bash
# apply-config.sh — Push Pi-hole operational configs to the running instance
#
# Reads config files from ./config/ and applies them to Pi-hole:
#   1. Adlists     — blocklist subscriptions (config/adlists.csv)
#   2. Whitelist   — allowed domains (config/whitelist.txt)
#   3. Blacklist   — regex block patterns (config/regex-blacklist.txt)
#   4. dnsmasq     — custom DNS/performance config (config/99-custom.conf)
#   5. Gravity     — rebuild blocklist database
#
# Runs from your workstation over SSH to the Synology.
#
# Usage:
#   ./apply-config.sh              # Apply everything
#   ./apply-config.sh --adlists    # Only update adlists
#   ./apply-config.sh --whitelist  # Only update whitelist
#   ./apply-config.sh --regex      # Only update regex blacklist
#   ./apply-config.sh --dnsmasq    # Only update dnsmasq config
#   ./apply-config.sh --dry-run    # Show what would change, don't apply

set -euo pipefail

# ═════════════════════════════════════════════════════════════════════
# CONFIGURATION — Edit these to match your setup
# ═════════════════════════════════════════════════════════════════════
NAS_USER="your-username"
NAS_IP="192.168.1.2"
NAS_HOST="${NAS_USER}@${NAS_IP}"
NAS_DIR="/volume1/docker/pihole"
CONTAINER="pihole"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
PIHOLE_IP="192.168.1.53"
# ═════════════════════════════════════════════════════════════════════

ok()   { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*" >&2; exit 1; }
warn() { printf "  \033[33m⚠\033[0m %s\n" "$*"; }
info() { printf "  → %s\n" "$*"; }
step() { printf "\n\033[1m[%s]\033[0m %s\n" "$1" "$2"; }

# Parse flags
DO_ALL=true
DO_ADLISTS=false
DO_WHITELIST=false
DO_REGEX=false
DO_DNSMASQ=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --adlists)   DO_ALL=false; DO_ADLISTS=true ;;
        --whitelist) DO_ALL=false; DO_WHITELIST=true ;;
        --regex)     DO_ALL=false; DO_REGEX=true ;;
        --dnsmasq)   DO_ALL=false; DO_DNSMASQ=true ;;
        --dry-run)   DRY_RUN=true ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

$DO_ALL && { DO_ADLISTS=true; DO_WHITELIST=true; DO_REGEX=true; DO_DNSMASQ=true; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Pi-hole Config Apply              ║"
echo "╚══════════════════════════════════════╝"

# Helper: run pihole-FTL sqlite3 inside the container
# -n is critical: without it, ssh reads from stdin and eats
# the file being piped into the while-read loop.
pihole_sql() {
    ssh -n "${NAS_HOST}" "sudo docker exec ${CONTAINER} pihole-FTL sqlite3 /etc/pihole/gravity.db \"$1\""
}

# --- Preflight ---
step "0" "Preflight"
ssh -o ConnectTimeout=5 -o BatchMode=yes "${NAS_HOST}" "true" 2>/dev/null \
    || fail "Cannot SSH to ${NAS_HOST}"
ok "SSH connection"

ssh "${NAS_HOST}" "sudo docker ps --format '{{.Names}}' | grep -q '^${CONTAINER}$'" \
    || fail "Container '${CONTAINER}' is not running"
ok "Container running"

# ═════════════════════════════════════════════════════════════════════
# ADLISTS
# ═════════════════════════════════════════════════════════════════════
if $DO_ADLISTS; then
    step "1" "Adlists (blocklist subscriptions)"

    if [[ ! -f "${CONFIG_DIR}/adlists.csv" ]]; then
        warn "config/adlists.csv not found — skipping"
    else
        # Read current adlists
        CURRENT=$(pihole_sql "SELECT address FROM adlist;" 2>/dev/null || echo "")

        ADDED=0
        SKIPPED=0

        while IFS=',' read -r url enabled comment; do
            # Skip comments and empty lines
            [[ "$url" =~ ^#.*$ ]] || [[ -z "$url" ]] && continue

            # Trim whitespace
            url=$(echo "$url" | xargs)
            enabled=$(echo "$enabled" | xargs)
            comment=$(echo "$comment" | xargs)

            if echo "$CURRENT" | grep -qF "$url"; then
                SKIPPED=$((SKIPPED + 1))
                continue
            fi

            if $DRY_RUN; then
                info "[dry-run] Would add: ${comment:-$url} (enabled=${enabled})"
            else
                pihole_sql "INSERT INTO adlist (address, enabled, comment) VALUES ('${url}', ${enabled:-1}, '${comment}');" 2>/dev/null
            fi
            ADDED=$((ADDED + 1))
        done < "${CONFIG_DIR}/adlists.csv"

        ok "Adlists: ${ADDED} added, ${SKIPPED} already present"
    fi
fi

# ═════════════════════════════════════════════════════════════════════
# WHITELIST
# ═════════════════════════════════════════════════════════════════════
if $DO_WHITELIST; then
    step "2" "Whitelist (allowed domains)"

    if [[ ! -f "${CONFIG_DIR}/whitelist.txt" ]]; then
        warn "config/whitelist.txt not found — skipping"
    else
        # domainlist type 0 = exact whitelist
        CURRENT=$(pihole_sql "SELECT domain FROM domainlist WHERE type = 0;" 2>/dev/null || echo "")

        ADDED=0
        SKIPPED=0

        while IFS= read -r domain; do
            [[ "$domain" =~ ^#.*$ ]] || [[ -z "$domain" ]] && continue
            domain=$(echo "$domain" | xargs)

            if echo "$CURRENT" | grep -qxF "$domain"; then
                SKIPPED=$((SKIPPED + 1))
                continue
            fi

            if $DRY_RUN; then
                info "[dry-run] Would whitelist: ${domain}"
            else
                pihole_sql "INSERT OR IGNORE INTO domainlist (domain, type, enabled, comment) VALUES ('${domain}', 0, 1, 'Auto-added by apply-config.sh');" 2>/dev/null
            fi
            ADDED=$((ADDED + 1))
        done < "${CONFIG_DIR}/whitelist.txt"

        ok "Whitelist: ${ADDED} added, ${SKIPPED} already present"
    fi
fi

# ═════════════════════════════════════════════════════════════════════
# REGEX BLACKLIST
# ═════════════════════════════════════════════════════════════════════
if $DO_REGEX; then
    step "3" "Regex blacklist (pattern-based blocking)"

    if [[ ! -f "${CONFIG_DIR}/regex-blacklist.txt" ]]; then
        warn "config/regex-blacklist.txt not found — skipping"
    else
        # domainlist type 3 = regex blacklist
        CURRENT=$(pihole_sql "SELECT domain FROM domainlist WHERE type = 3;" 2>/dev/null || echo "")

        ADDED=0
        SKIPPED=0

        while IFS= read -r pattern; do
            [[ "$pattern" =~ ^#.*$ ]] || [[ -z "$pattern" ]] && continue
            pattern=$(echo "$pattern" | xargs)

            if echo "$CURRENT" | grep -qxF "$pattern"; then
                SKIPPED=$((SKIPPED + 1))
                continue
            fi

            # Escape single quotes for SQL
            escaped_pattern="${pattern//\'/\'\'}"

            if $DRY_RUN; then
                info "[dry-run] Would add regex: ${pattern}"
            else
                pihole_sql "INSERT OR IGNORE INTO domainlist (domain, type, enabled, comment) VALUES ('${escaped_pattern}', 3, 1, 'Auto-added by apply-config.sh');" 2>/dev/null
            fi
            ADDED=$((ADDED + 1))
        done < "${CONFIG_DIR}/regex-blacklist.txt"

        ok "Regex blacklist: ${ADDED} added, ${SKIPPED} already present"
    fi
fi

# ═════════════════════════════════════════════════════════════════════
# DNSMASQ CONFIG
# ═════════════════════════════════════════════════════════════════════
if $DO_DNSMASQ; then
    step "4" "Custom dnsmasq configuration"

    if [[ ! -f "${CONFIG_DIR}/99-custom.conf" ]]; then
        warn "config/99-custom.conf not found — skipping"
    else
        # Ensure etc_dnsmasq_d is enabled in pihole.toml
        DNSMASQ_D=$(ssh "${NAS_HOST}" "sudo docker exec ${CONTAINER} pihole-FTL --config misc.etc_dnsmasq_d 2>/dev/null" || echo "")
        if echo "$DNSMASQ_D" | grep -qi "false"; then
            if $DRY_RUN; then
                info "[dry-run] Would enable misc.etc_dnsmasq_d in pihole.toml"
            else
                ssh "${NAS_HOST}" "sudo docker exec ${CONTAINER} pihole-FTL --config misc.etc_dnsmasq_d true" >/dev/null 2>&1
                ok "Enabled misc.etc_dnsmasq_d"
            fi
        fi

        if $DRY_RUN; then
            info "[dry-run] Would copy 99-custom.conf to /etc/dnsmasq.d/"
        else
            # Upload to NAS, then copy into container volume
            cat "${CONFIG_DIR}/99-custom.conf" \
                | ssh "${NAS_HOST}" "cat > ${NAS_DIR}/etc-dnsmasq.d/99-custom.conf"
            ok "99-custom.conf deployed to /etc/dnsmasq.d/"
        fi
    fi
fi

# ═════════════════════════════════════════════════════════════════════
# REBUILD GRAVITY
# ═════════════════════════════════════════════════════════════════════
if $DO_ADLISTS && ! $DRY_RUN; then
    step "5" "Rebuilding gravity (downloading blocklists)"
    info "This may take 1-2 minutes..."
    ssh "${NAS_HOST}" "sudo docker exec ${CONTAINER} pihole -g 2>&1" | while IFS= read -r line; do
        # Show progress lines
        case "$line" in
            *"gravity"*|*"adlist"*|*"downloaded"*|*"Done"*|*"Number"*|*"unique"*|*"Neutrino"*)
                info "$line" ;;
        esac
    done
    ok "Gravity rebuilt"
elif $DO_DNSMASQ && ! $DRY_RUN; then
    step "5" "Restarting Pi-hole DNS"
    ssh "${NAS_HOST}" "sudo docker exec ${CONTAINER} pihole reloaddns 2>/dev/null" \
        || ssh "${NAS_HOST}" "sudo docker restart ${CONTAINER} 2>/dev/null"
    ok "DNS reloaded (picks up new dnsmasq config)"
fi

# ═════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════
echo ""
if $DRY_RUN; then
    echo "════════════════════════════════════════"
    echo "  Dry run complete — no changes made."
    echo "  Re-run without --dry-run to apply."
    echo "════════════════════════════════════════"
else
    echo "════════════════════════════════════════"
    echo "  Configuration applied!"
    echo ""
    echo "  Web UI:  http://${PIHOLE_IP}/admin"
    echo "  Verify:  ./verify.sh"
    echo "════════════════════════════════════════"
fi
