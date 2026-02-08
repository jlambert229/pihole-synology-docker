#!/usr/bin/env bash
# backup.sh — Automated Pi-hole backup for cron
#
# Creates two backup artifacts per run:
#   1. Teleporter export  — Pi-hole's built-in config/list backup (small, portable)
#   2. Volume snapshot     — Full tar of mounted data dirs (everything on disk)
#
# Designed for cron — silent on success, logs errors to stderr + syslog.
# Old backups are rotated automatically.
#
# Usage:
#   sudo bash backup.sh              # Run manually
#   sudo bash backup.sh --verbose    # Run with output (for testing)
#
# Cron (daily at 3am):
#   0 3 * * * /volume1/docker/pihole/backup.sh 2>&1 | logger -t pihole-backup
#
# Restore:
#   See restore instructions at bottom of this script, or README.

set -euo pipefail

# ═════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═════════════════════════════════════════════════════════════════════
CONTAINER="pihole"
DATA_DIR="/volume1/docker/pihole"
BACKUP_ROOT="${DATA_DIR}/backups"
RETAIN_DAYS=14                     # Delete backups older than this
TIMESTAMP="$(date +%Y-%m-%d_%H%M)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
VERBOSE=false
# ═════════════════════════════════════════════════════════════════════

[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

log()  { $VERBOSE && echo "[backup] $*" || true; }
err()  { echo "[backup] ERROR: $*" >&2; }

# --- Preflight ---
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    err "Container '${CONTAINER}' is not running — skipping backup"
    exit 1
fi

mkdir -p "${BACKUP_DIR}"
log "Backup directory: ${BACKUP_DIR}"

# --- 1. Teleporter export ---
# Pi-hole v6 uses pihole-FTL for teleporter exports.
# This captures: settings, adlists, blocklists, whitelist/blacklist,
# custom DNS, CNAME records, DHCP leases, and audit log.
#
# v6 behavior: `pihole-FTL --teleporter` writes a .zip to cwd and prints the filename.
log "Running teleporter export..."
TELEPORTER_FILE="${BACKUP_DIR}/pihole-teleporter.zip"
TELEPORTER_OUTPUT=$(docker exec "${CONTAINER}" bash -c \
    "cd /tmp && pihole-FTL --teleporter 2>/dev/null" 2>/dev/null || echo "")
TELEPORTER_NAME=$(echo "${TELEPORTER_OUTPUT}" | grep -o 'pi-hole.*\.zip' || echo "")

if [[ -n "${TELEPORTER_NAME}" ]]; then
    # Copy the zip out of the container
    docker cp "${CONTAINER}:/tmp/${TELEPORTER_NAME}" "${TELEPORTER_FILE}" 2>/dev/null
    # Clean up inside the container
    docker exec "${CONTAINER}" rm -f "/tmp/${TELEPORTER_NAME}" 2>/dev/null || true

    if [[ -s "${TELEPORTER_FILE}" ]]; then
        SIZE=$(du -h "${TELEPORTER_FILE}" | cut -f1)
        log "Teleporter export: ${SIZE}"
    else
        err "Teleporter export produced empty file — falling back to volume-only backup"
        rm -f "${TELEPORTER_FILE}"
    fi
else
    err "Teleporter export failed — falling back to volume-only backup"
    rm -f "${TELEPORTER_FILE}"
fi

# --- 2. Volume snapshot ---
# Tars the actual mounted data: gravity.db, pihole.toml, dnsmasq configs, etc.
# This is the "belt" to teleporter's "suspenders".
log "Snapshotting volumes..."
VOLUME_FILE="${BACKUP_DIR}/pihole-volumes.tar.gz"
tar czf "${VOLUME_FILE}" \
    -C "${DATA_DIR}" \
    --exclude='backups' \
    etc-pihole etc-dnsmasq.d \
    2>/dev/null

SIZE=$(du -h "${VOLUME_FILE}" | cut -f1)
log "Volume snapshot: ${SIZE}"

# --- 3. Metadata ---
# Record what was running so restores have context
cat > "${BACKUP_DIR}/backup-info.txt" <<EOF
Pi-hole Backup
==============
Date:       $(date -Iseconds)
Host:       $(hostname)
Container:  ${CONTAINER}
Image:      $(docker inspect "${CONTAINER}" --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
Image ID:   $(docker inspect "${CONTAINER}" --format '{{.Image}}' 2>/dev/null | cut -c8-19 || echo "unknown")
Uptime:     $(docker inspect "${CONTAINER}" --format '{{.State.StartedAt}}' 2>/dev/null || echo "unknown")

Contents:
  pihole-teleporter.zip     — Pi-hole settings/lists (restore via web UI or CLI)
  pihole-volumes.tar.gz     — Raw /etc/pihole + /etc/dnsmasq.d volume data
  backup-info.txt           — This file

Restore (teleporter — preferred):
  Web UI → Settings → Teleporter → Import → select pihole-teleporter.zip

Restore (volume — nuclear option):
  docker-compose down
  tar xzf pihole-volumes.tar.gz -C ${DATA_DIR}/
  docker-compose up -d
EOF

log "Metadata written"

# --- 4. Rotate old backups ---
DELETED=0
if [[ -d "${BACKUP_ROOT}" ]]; then
    while IFS= read -r old_dir; do
        rm -rf "$old_dir"
        ((DELETED++))
        log "Rotated: $(basename "$old_dir")"
    done < <(find "${BACKUP_ROOT}" -maxdepth 1 -mindepth 1 -type d -mtime +${RETAIN_DAYS} 2>/dev/null)
fi
log "Rotated ${DELETED} old backup(s) (retain: ${RETAIN_DAYS} days)"

# --- Summary ---
TOTAL_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
log "Done — ${TOTAL_SIZE} total in ${BACKUP_DIR}"
