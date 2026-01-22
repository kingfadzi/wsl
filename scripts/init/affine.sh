#!/bin/bash
# Initialize AFFiNE during docker build
# This script runs database migrations and sets up the admin user
set -e

# Source NVM to get node/npm in PATH
export NVM_DIR=/opt/nvm
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Verify node is available
if ! command -v node &>/dev/null; then
    echo "ERROR: node not found after sourcing NVM"
    exit 1
fi
echo "Using Node.js $(node --version)"

echo "=== Initializing AFFiNE ==="

# AppStream PostgreSQL paths
PGDATA=/var/lib/pgsql/data

cd /opt/affine

# Set environment variables for AFFiNE
export NODE_ENV=production
export AFFINE_ADMIN_EMAIL="admin@localhost"
export AFFINE_ADMIN_PASSWORD="password"
export DATABASE_URL="postgres://affine:affine@localhost:5432/affine"
export POSTGRES_HOST="localhost"
export REDIS_SERVER_HOST="localhost"

# Create runtime directory for Unix socket
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql

# Start PostgreSQL (without -w, then wait manually)
echo "Starting PostgreSQL..."
su - postgres -c "pg_ctl -D $PGDATA -l /var/lib/pgsql/pgstartup.log start"

# Start Redis
redis-server --daemonize yes

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..60}; do
    if su - postgres -c "psql -c 'SELECT 1'" &>/dev/null; then
        echo "PostgreSQL is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "PostgreSQL failed to start. Log:"
        cat /var/lib/pgsql/pgstartup.log || true
        exit 1
    fi
    sleep 1
done

# Run AFFiNE install script if it exists
if [[ -x ./install.sh ]]; then
    echo "Running AFFiNE install script..."
    if ! ./install.sh; then
        echo "WARNING: install.sh failed (may be expected if already installed)"
    fi
fi

# Run migrations if there's a migrate script
if [[ -x ./migrate.sh ]]; then
    echo "Running AFFiNE migrations..."
    if ! ./migrate.sh; then
        echo "WARNING: migrate.sh failed - migrations may need to run at first boot"
    fi
fi

# Stop services
redis-cli shutdown || true
su - postgres -c "pg_ctl -D $PGDATA stop -m fast" || true

# Create .env for runtime (AFFiNE may require this over env vars)
cat > /opt/affine/.env << 'EOF'
NODE_ENV=production
DATABASE_URL=postgres://affine:affine@localhost:5432/affine
POSTGRES_HOST=localhost
REDIS_SERVER_HOST=localhost
AFFINE_SERVER_PORT=3010
AFFINE_SERVER_HOST=0.0.0.0
EOF

echo "=== AFFiNE initialization complete ==="
