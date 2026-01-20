#!/bin/bash
# Initialize PostgreSQL databases during docker build
# This script runs at build time to create databases for all applications
set -e

echo "=== Initializing PostgreSQL databases ==="

# AppStream PostgreSQL paths
PGDATA=/var/lib/pgsql/data

# Start PostgreSQL (without -w, then wait manually)
echo "Starting PostgreSQL..."
su - postgres -c "pg_ctl -D $PGDATA -l /var/lib/pgsql/pgstartup.log start"

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

# Create databases and users for each application
for db in superset metabase affine; do
    echo "Creating database: $db"
    su - postgres -c "psql -c \"CREATE USER $db WITH PASSWORD '$db';\"" || true
    su - postgres -c "psql -c \"CREATE DATABASE $db OWNER $db;\"" || true
    su - postgres -c "psql -d $db -c \"GRANT ALL ON SCHEMA public TO $db;\"" || true
done

# Stop PostgreSQL
su - postgres -c "pg_ctl -D $PGDATA stop -m fast" || true

echo "=== PostgreSQL initialization complete ==="
