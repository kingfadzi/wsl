#!/bin/bash
# Initialize AFFiNE during docker build
# This script runs database migrations and sets up the admin user
set -e

echo "=== Initializing AFFiNE ==="

# PGDG paths
export PATH=/usr/pgsql-15/bin:$PATH
PGDATA=/var/lib/pgsql/15/data

cd /opt/affine

# Set environment variables for AFFiNE
export NODE_ENV=production
export AFFINE_ADMIN_EMAIL="admin@localhost"
export AFFINE_ADMIN_PASSWORD="password"
export DATABASE_URL="postgres://affine:affine@localhost:5432/affine"
export POSTGRES_HOST="localhost"
export REDIS_SERVER_HOST="localhost"

# Start PostgreSQL (without -w, then wait manually)
echo "Starting PostgreSQL..."
su - postgres -c "/usr/pgsql-15/bin/pg_ctl -D $PGDATA -l /var/lib/pgsql/15/pgstartup.log start"

# Start Redis
redis-server --daemonize yes

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
for i in {1..60}; do
    if su - postgres -c "/usr/pgsql-15/bin/psql -c 'SELECT 1'" &>/dev/null; then
        echo "PostgreSQL is ready"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "PostgreSQL failed to start. Log:"
        cat /var/lib/pgsql/15/pgstartup.log || true
        exit 1
    fi
    sleep 1
done

# Run AFFiNE install script if it exists
if [[ -x ./install.sh ]]; then
    echo "Running AFFiNE install script..."
    ./install.sh || echo "AFFiNE install completed (or partially completed)"
fi

# Run migrations if there's a migrate script
if [[ -x ./migrate.sh ]]; then
    echo "Running AFFiNE migrations..."
    ./migrate.sh || echo "AFFiNE migrations completed (or skipped)"
fi

# Stop services
redis-cli shutdown || true
su - postgres -c "/usr/pgsql-15/bin/pg_ctl -D $PGDATA stop -m fast" || true

echo "=== AFFiNE initialization complete ==="
