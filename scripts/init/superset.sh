#!/bin/bash
# Initialize Apache Superset during docker build
# This script runs database migrations and creates an admin user
set -e

echo "=== Initializing Apache Superset ==="

# AppStream PostgreSQL paths
PGDATA=/var/lib/pgsql/data

# Activate the Superset virtual environment
source /opt/superset/venv/bin/activate

# Set environment variables
export SUPERSET_CONFIG_PATH=/opt/superset/config/superset_config.py
export FLASK_APP="superset.app:create_app()"

# Create runtime directory for Unix socket
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql

# Start PostgreSQL (without -w, then wait manually)
echo "Starting PostgreSQL..."
su - postgres -c "pg_ctl -D $PGDATA -l /var/lib/pgsql/pgstartup.log start"

# Start Redis
redis-server --daemonize yes

# Wait for PostgreSQL to be ready (longer timeout)
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

# Create upload directory
mkdir -p /opt/superset/uploads

# Run database migrations
echo "Running Superset database migrations..."
superset db upgrade

# Create admin user (ignore error if already exists)
echo "Creating admin user..."
superset fab create-admin \
    --username admin \
    --firstname Admin \
    --lastname User \
    --email admin@localhost \
    --password admin || echo "Admin user may already exist"

# Initialize Superset
echo "Initializing Superset..."
superset init

# Stop services
redis-cli shutdown || true
su - postgres -c "pg_ctl -D $PGDATA stop -m fast" || true

deactivate

echo "=== Superset initialization complete ==="
