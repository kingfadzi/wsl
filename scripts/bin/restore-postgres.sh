#!/bin/bash
# PostgreSQL restore script
# Installed to: /usr/local/bin/restore_postgres.sh
set -euo pipefail

# Load config from system manifest
MANIFEST="/etc/wsl-manifest"
if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Manifest not found: $MANIFEST"
    echo "Run wsl_setup.ps1 and tools.sh to create it."
    exit 1
fi
source "$MANIFEST"

# Defaults (manifest provides: BACKUP_DIR, PG_PORT, DISTRO_NAME)
BACKUP_BASE_DIR="${BACKUP_DIR:-/var/backups/postgresql}"
DEFAULT_HOST="localhost"
DEFAULT_PORT="${PG_PORT:-5432}"
LOG_FILE="/var/log/postgresql_restore.log"

# Use host-specific backup directory (hostname-distro)
HOST_ID="$(hostname)-${DISTRO_NAME:-unknown}"
BACKUP_DIR="${BACKUP_BASE_DIR}/${HOST_ID}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 [options] [database] [backup_file]"
    echo ""
    echo "Options:"
    echo "  -h, --host HOST    PostgreSQL host (default: $DEFAULT_HOST)"
    echo "  -p, --port PORT    PostgreSQL port (default: $DEFAULT_PORT)"
    echo "  -U, --user USER    DB username (enables password auth for remote)"
    echo "  --help             Show this help"
    echo ""
    echo "Arguments:"
    echo "  database           Database to restore (superset, affine)"
    echo "                     If not specified, will prompt for selection"
    echo "  backup_file        Specific backup file (optional, defaults to latest)"
    echo ""
    echo "Examples:"
    echo "  $0                                         # Interactive mode (local)"
    echo "  $0 superset                                # Restore latest superset backup"
    echo "  $0 -h remotehost -U dbuser affine          # Restore to remote server"
    echo "  $0 affine affine_20260117.dump             # Restore specific backup"
    echo ""
    echo "For remote restores, set PGPASSWORD env var or use ~/.pgpass file"
    echo ""
    echo "Available backups:"
    ls -lt "$BACKUP_DIR"/*.dump 2>/dev/null | head -10 || echo "  No backups found"
    exit 0
}

PG_HOST="$DEFAULT_HOST"
PG_PORT="$DEFAULT_PORT"
PG_USER=""
DATABASE=""
BACKUP_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host) PG_HOST="$2"; shift 2 ;;
        -p|--port) PG_PORT="$2"; shift 2 ;;
        -U|--user) PG_USER="$2"; shift 2 ;;
        --help) usage ;;
        -*) echo "Unknown option: $1"; usage ;;
        *)
            if [[ -z "$DATABASE" ]]; then
                DATABASE="$1"
            else
                BACKUP_FILE="$1"
            fi
            shift
            ;;
    esac
done

# Helper functions for local peer auth vs remote password auth
run_psql() {
    local cmd="$1"
    if [[ -n "$PG_USER" ]]; then
        # Remote: use TCP with password auth
        psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -c "$cmd"
    else
        # Local: use Unix socket with peer auth (no -h flag)
        runuser -l postgres -c "psql -p $PG_PORT -c \"$cmd\""
    fi
}

run_pg_restore() {
    local db="$1"
    local file="$2"
    if [[ -n "$PG_USER" ]]; then
        # Remote: use TCP with password auth
        pg_restore -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$db" "$file"
    else
        # Local: use Unix socket with peer auth (no -h flag)
        runuser -l postgres -c "pg_restore -p $PG_PORT -d $db $file"
    fi
}

# Interactive mode - select database if not provided
if [[ -z "$DATABASE" ]]; then
    echo "Available databases:"
    echo "  1) superset"
    echo "  2) affine"
    read -p "Select database to restore [1-2]: " choice
    case $choice in
        1) DATABASE="superset" ;;
        2) DATABASE="affine" ;;
        *) echo "Invalid selection"; exit 1 ;;
    esac
fi

# Find backup file
if [[ -z "$BACKUP_FILE" ]]; then
    echo ""
    echo "Available backups for $DATABASE:"
    BACKUPS=($(ls -t "${BACKUP_DIR}/${DATABASE}_"*.dump 2>/dev/null))
    if [[ ${#BACKUPS[@]} -eq 0 ]]; then
        echo "  No backups found for $DATABASE"
        exit 1
    fi

    for i in "${!BACKUPS[@]}"; do
        SIZE=$(du -h "${BACKUPS[$i]}" | cut -f1)
        DATE=$(stat -c %y "${BACKUPS[$i]}" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo "  $((i+1))) $(basename "${BACKUPS[$i]}") ($SIZE, $DATE)"
    done

    read -p "Select backup [1-${#BACKUPS[@]}] (default: 1 - latest): " choice
    choice=${choice:-1}
    if [[ $choice -lt 1 || $choice -gt ${#BACKUPS[@]} ]]; then
        echo "Invalid selection"
        exit 1
    fi
    BACKUP_FILE="${BACKUPS[$((choice-1))]}"
else
    # Check if full path or just filename
    if [[ ! -f "$BACKUP_FILE" ]]; then
        BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
    fi
    if [[ ! -f "$BACKUP_FILE" ]]; then
        echo "ERROR: Backup file not found: $BACKUP_FILE"
        exit 1
    fi
fi

BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

# Show confirmation with all details
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ⚠️  DATABASE RESTORE WARNING ⚠️                 ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  This will DESTROY the existing database and replace it   ║"
echo "║  with data from the backup file.                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Database:    $DATABASE"
echo "  Server:      $PG_HOST:$PG_PORT"
echo "  Backup file: $(basename "$BACKUP_FILE")"
echo "  Backup size: $BACKUP_SIZE"
echo ""

read -p "Type the database name to confirm restore: " confirm
if [[ "$confirm" != "$DATABASE" ]]; then
    echo "Database name does not match. Restore cancelled."
    exit 0
fi

log "Starting restore of $DATABASE from $BACKUP_FILE"

# Stop dependent service for this database only
log "Stopping dependent service..."
case $DATABASE in
    superset)
        systemctl stop superset-web 2>/dev/null || true
        systemctl stop superset-worker 2>/dev/null || true
        ;;
    affine)
        systemctl stop affine 2>/dev/null || true
        ;;
esac

# Drop and recreate database
log "Dropping database: $DATABASE"
run_psql "DROP DATABASE IF EXISTS ${DATABASE};"

log "Creating database: $DATABASE"
run_psql "CREATE DATABASE ${DATABASE} OWNER ${DATABASE};"

# Restore from backup
log "Restoring from backup..."
if run_pg_restore "$DATABASE" "$BACKUP_FILE"; then
    log "Restore complete!"
else
    log "ERROR: Restore failed"
    exit 1
fi

# Restart the specific service
log "Restarting service..."
case $DATABASE in
    superset)
        systemctl start superset-web 2>/dev/null || true
        systemctl start superset-worker 2>/dev/null || true
        ;;
    affine)
        systemctl start affine 2>/dev/null || true
        ;;
esac

echo ""
log "✓ Restore complete for database: $DATABASE"
