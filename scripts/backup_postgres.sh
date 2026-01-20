#!/bin/bash
# PostgreSQL backup script
# Installed to: /usr/local/bin/backup_postgres.sh
set -euo pipefail

# Load config from system manifest
MANIFEST="/etc/wsl-manifest"
if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Manifest not found: $MANIFEST"
    echo "Run wsl_setup.ps1 and tools.sh to create it."
    exit 1
fi
source "$MANIFEST"

# Defaults (manifest provides: BACKUP_DIR, PG_PORT, DATABASES, RETENTION_DAYS, DISTRO_NAME)
BACKUP_BASE_DIR="${BACKUP_DIR:-/var/backups/postgresql}"
ALL_DATABASES="${DATABASES:-}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
DEFAULT_HOST="localhost"
DEFAULT_PORT="${PG_PORT:-5432}"
LOG_FILE="/var/log/postgresql_backup.log"

# Create host-specific backup directory (hostname-distro)
HOST_ID="$(hostname)-${DISTRO_NAME:-unknown}"
BACKUP_DIR="${BACKUP_BASE_DIR}/${HOST_ID}"
mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

usage() {
    echo "Usage: $0 [options] [database]"
    echo ""
    echo "Options:"
    echo "  -h, --host HOST    PostgreSQL host (default: $DEFAULT_HOST)"
    echo "  -p, --port PORT    PostgreSQL port (default: $DEFAULT_PORT)"
    echo "  -U, --user USER    DB username (enables password auth for remote)"
    echo "  -a, --all          Backup all databases (for cron, local only)"
    echo "  -y, --yes          Skip confirmation"
    echo "  --help             Show this help"
    echo ""
    echo "Arguments:"
    echo "  database           Database to backup (superset, metabase, affine)"
    echo "                     If not specified, will prompt for selection"
    echo ""
    echo "Examples:"
    echo "  $0 superset                         # Local backup (peer auth)"
    echo "  $0 -h remotehost -U dbuser superset # Remote backup (password auth)"
    echo "  $0 --all --yes                      # Backup all local (for cron)"
    echo ""
    echo "For remote backups, set PGPASSWORD env var or use ~/.pgpass file"
    exit 0
}

PG_HOST="$DEFAULT_HOST"
PG_PORT="$DEFAULT_PORT"
PG_USER=""
DATABASE=""
BACKUP_ALL=false
SKIP_CONFIRM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host) PG_HOST="$2"; shift 2 ;;
        -p|--port) PG_PORT="$2"; shift 2 ;;
        -U|--user) PG_USER="$2"; shift 2 ;;
        -a|--all) BACKUP_ALL=true; shift ;;
        -y|--yes) SKIP_CONFIRM=true; shift ;;
        --help) usage ;;
        -*) echo "Unknown option: $1"; usage ;;
        *) DATABASE="$1"; shift ;;
    esac
done

# Helper function to run pg_dump (local peer auth vs remote password auth)
run_pg_dump() {
    local db="$1"
    local output="$2"
    if [[ -n "$PG_USER" ]]; then
        # Remote: use TCP with password auth (use PGPASSWORD or .pgpass)
        pg_dump -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -Fc "$db" > "$output"
    else
        # Local: use Unix socket with peer auth (no -h flag)
        runuser -l postgres -c "pg_dump -p $PG_PORT -Fc $db" > "$output"
    fi
}

# If backing up all (cron mode - local only)
if [[ "$BACKUP_ALL" == "true" ]]; then
    if [[ -n "$PG_USER" ]]; then
        log "ERROR: --all mode only supports local backups (don't use -U)"
        exit 1
    fi
    DATE=$(date +%Y%m%d_%H%M%S)
    log "Starting backup of all databases..."
    for db in $ALL_DATABASES; do
        BACKUP_FILE="${BACKUP_DIR}/${db}_${DATE}.dump"
        log "Backing up: $db"
        if run_pg_dump "$db" "$BACKUP_FILE"; then
            chmod 640 "$BACKUP_FILE"
            chown postgres:postgres "$BACKUP_FILE"
            log "Complete: $BACKUP_FILE"
        else
            log "ERROR: Failed to backup $db"
        fi
    done
    log "Cleaning up backups older than ${RETENTION_DAYS} days..."
    find "$BACKUP_DIR" -name "*.dump" -type f -mtime +${RETENTION_DAYS} -delete
    log "Backup process complete"
    exit 0
fi

# Interactive mode - select database if not provided
if [[ -z "$DATABASE" ]]; then
    echo "Available databases:"
    echo "  1) superset"
    echo "  2) metabase"
    echo "  3) affine"
    read -p "Select database [1-3]: " choice
    case $choice in
        1) DATABASE="superset" ;;
        2) DATABASE="metabase" ;;
        3) DATABASE="affine" ;;
        *) echo "Invalid selection"; exit 1 ;;
    esac
fi

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${DATABASE}_${DATE}.dump"

# Show confirmation
echo ""
echo "=== Backup Details ==="
echo "  Database: $DATABASE"
echo "  Host:     $PG_HOST"
echo "  Port:     $PG_PORT"
[[ -n "$PG_USER" ]] && echo "  User:     $PG_USER (password auth)"
[[ -z "$PG_USER" ]] && echo "  Auth:     peer (local postgres user)"
echo "  Output:   $BACKUP_FILE"
echo ""

if [[ "$SKIP_CONFIRM" != "true" ]]; then
    read -p "Proceed with backup? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && { echo "Cancelled"; exit 0; }
fi

log "Backing up database: $DATABASE"
if run_pg_dump "$DATABASE" "$BACKUP_FILE"; then
    chmod 640 "$BACKUP_FILE"
    log "Backup complete: $BACKUP_FILE"
    echo "Backup saved to: $BACKUP_FILE"
else
    log "ERROR: Failed to backup $DATABASE"
    exit 1
fi
