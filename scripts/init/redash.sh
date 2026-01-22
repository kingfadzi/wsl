#!/bin/bash
# Initialize Redash during docker build
# This script creates the .env file and initializes the database
set -e

echo "=== Initializing Redash ==="

# AppStream PostgreSQL paths
PGDATA=/var/lib/pgsql/data

cd /opt/redash

# Generate secrets
COOKIE_SECRET=$(openssl rand -hex 32)
SECRET_KEY=$(openssl rand -hex 32)

# Create .env file for runtime
cat > /opt/redash/redash.env << EOF
# Redash configuration
REDASH_DATABASE_URL=postgresql://redash:redash@localhost:5432/redash
REDASH_REDIS_URL=redis://localhost:6379/0
REDASH_COOKIE_SECRET=${COOKIE_SECRET}
REDASH_SECRET_KEY=${SECRET_KEY}

# Optional settings
REDASH_LOG_LEVEL=INFO
REDASH_WEB_WORKERS=4
REDASH_GUNICORN_TIMEOUT=60
REDASH_BIND=0.0.0.0:5000
EOF

# Create runtime directory for Unix socket
mkdir -p /var/run/postgresql
chown postgres:postgres /var/run/postgresql

# Start PostgreSQL
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

# Initialize Redash database tables
echo "Initializing Redash database..."
./bin/init_db

# Stop services
redis-cli shutdown || true
su - postgres -c "pg_ctl -D $PGDATA stop -m fast" || true

echo "=== Redash initialization complete ==="
