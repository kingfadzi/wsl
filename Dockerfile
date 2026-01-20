FROM almalinux:9

# ===== Build args =====
ARG PROFILE=vpn
ARG PYTHON_VERSION=3.11
ARG NODE_VERSION=22
ARG JAVA_VERSION=21
ARG SUPERSET_VERSION=6.0.0
ARG METABASE_VERSION=0.50.21
ARG AFFINE_VERSION=0.16.3
ARG DEFAULT_USER=fadzi
ARG DNS_SERVERS="8.8.8.8 8.8.4.4"
ARG PYPI_INDEX_URL=
ARG PYPI_TRUSTED_HOST=
ARG NPM_REGISTRY=
ARG MAVEN_REPO_URL=
ARG BACKUP_DIR=/mnt/f/backups/postgresql

# ===== Base packages =====
RUN dnf install -y --allowerasing \
    git vim curl wget jq hostname bind-utils \
    iputils net-tools procps-ng findutils \
    sudo passwd cronie gcc gcc-c++ make \
    ca-certificates tar gzip openssl \
    && dnf clean all

# ===== WSL config =====
COPY config/wsl.conf /etc/wsl.conf

# ===== DNS (baked in per profile) =====
# Docker mounts /etc/resolv.conf during build, so we write to a staging file
# and copy it on first boot via profile.d script
ARG DNS_SERVERS
RUN for dns in ${DNS_SERVERS}; do echo "nameserver $dns" >> /etc/resolv.conf.wsl; done && \
    echo '#!/bin/bash' > /etc/profile.d/00-dns.sh && \
    echo '# Copy baked DNS config on first boot (wsl.conf has generateResolvConf=false)' >> /etc/profile.d/00-dns.sh && \
    echo 'if [ -f /etc/resolv.conf.wsl ] && ! grep -q "^nameserver" /etc/resolv.conf 2>/dev/null; then' >> /etc/profile.d/00-dns.sh && \
    echo '  sudo cp /etc/resolv.conf.wsl /etc/resolv.conf 2>/dev/null || true' >> /etc/profile.d/00-dns.sh && \
    echo 'fi' >> /etc/profile.d/00-dns.sh && \
    chmod 644 /etc/profile.d/00-dns.sh

# ===== CA Certificates (System) =====
# Three types of certs:
#   1. Corporate CA bundle (certs/*.pem) - copied directly to system trust
#   2. Zscaler certs (certs/*.cer) - converted from DER/PEM, combined into bundle
#   3. Java cacerts (certs/*.cacerts) - replaces Java trust store (handled after Java install)
COPY certs/ /tmp/certs/
ARG PROFILE
RUN CERTS_INSTALLED=0; \
    # Install corporate CA bundle files (always, both profiles) \
    if ls /tmp/certs/*.pem 2>/dev/null; then \
      for bundle in /tmp/certs/*.pem; do \
        echo "Installing CA bundle: $bundle"; \
        cp "$bundle" /etc/pki/ca-trust/source/anchors/; \
        CERTS_INSTALLED=1; \
      done; \
    fi; \
    # Install Zscaler certs (vpn profile only) \
    if [ "$PROFILE" = "vpn" ] && ls /tmp/certs/*.cer 2>/dev/null; then \
      BUNDLE="/etc/pki/ca-trust/source/anchors/zscaler-bundle.pem"; \
      : > "$BUNDLE"; \
      for cert in /tmp/certs/*.cer; do \
        echo "Converting Zscaler cert: $cert"; \
        openssl x509 -inform DER -in "$cert" >> "$BUNDLE" 2>/dev/null || \
        openssl x509 -in "$cert" >> "$BUNDLE"; \
        echo "" >> "$BUNDLE"; \
      done; \
      echo "Created Zscaler bundle with $(grep -c 'BEGIN CERTIFICATE' "$BUNDLE") certificate(s)"; \
      CERTS_INSTALLED=1; \
    fi; \
    # Update trust store if any certs installed \
    if [ "$CERTS_INSTALLED" = "1" ]; then \
      update-ca-trust extract; \
      echo "CA certificates installed into system trust store"; \
    fi

# ===== Proxy passthrough script (reads Windows env vars at login) =====
COPY scripts/proxy.sh /etc/profile.d/proxy.sh
RUN chmod 644 /etc/profile.d/proxy.sh

# ===== Runtimes =====
ARG PYTHON_VERSION
ARG NODE_VERSION
ARG JAVA_VERSION
RUN dnf module enable -y nodejs:${NODE_VERSION} \
    && dnf install -y \
       nodejs npm \
       python${PYTHON_VERSION} python${PYTHON_VERSION}-pip python${PYTHON_VERSION}-devel \
       java-${JAVA_VERSION}-openjdk java-${JAVA_VERSION}-openjdk-devel \
    && dnf clean all

# Set Python alternatives
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1 \
    && alternatives --install /usr/bin/pip pip /usr/bin/pip${PYTHON_VERSION} 1 \
    && alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip${PYTHON_VERSION} 1

# ===== Package registries (configure before installing packages) =====
ARG NPM_REGISTRY
RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi

# Install yarn (needed for AFFiNE)
RUN npm install -g yarn

# ===== Java cacerts (install org trust store after Java is available) =====
RUN if ls /tmp/certs/*.cacerts 2>/dev/null; then \
      JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java)))); \
      CACERTS_DST="$JAVA_HOME/lib/security/cacerts"; \
      for cacerts in /tmp/certs/*.cacerts; do \
        echo "Installing Java cacerts: $cacerts -> $CACERTS_DST"; \
        cp "$cacerts" "$CACERTS_DST"; \
        chmod 644 "$CACERTS_DST"; \
      done; \
    fi; \
    rm -rf /tmp/certs

# ===== PostgreSQL (from AppStream module) =====
RUN dnf module enable -y postgresql:15 \
    && dnf install -y postgresql-server postgresql-contrib \
    && dnf clean all

# Initialize PostgreSQL data directory
ENV PGDATA=/var/lib/pgsql/data
RUN mkdir -p $PGDATA && chown postgres:postgres $PGDATA && \
    su - postgres -c "initdb -D $PGDATA"

# Configure pg_hba.conf for peer auth (local) + md5 (network)
RUN sed -i 's/^\(local.*\)ident$/\1peer/' $PGDATA/pg_hba.conf \
    && sed -i 's/^\(host.*\)ident$/\1md5/' $PGDATA/pg_hba.conf

# ===== Redis =====
RUN dnf module enable -y redis:7 \
    && dnf install -y redis \
    && dnf clean all

RUN sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf

# ===== Create databases (requires postgres running, done via init script) =====
COPY scripts/init-postgres.sh /tmp/
RUN chmod +x /tmp/init-postgres.sh && /tmp/init-postgres.sh && rm /tmp/init-postgres.sh

# ===== Superset =====
RUN python3 -m venv /opt/superset/venv

# Configure pip: internal PyPI (if provided) with public fallback
ARG PYPI_INDEX_URL
ARG PYPI_TRUSTED_HOST
RUN if [ -n "$PYPI_INDEX_URL" ]; then \
      /opt/superset/venv/bin/pip config set global.index-url "$PYPI_INDEX_URL"; \
      /opt/superset/venv/bin/pip config set global.trusted-host "$PYPI_TRUSTED_HOST"; \
      /opt/superset/venv/bin/pip config set global.extra-index-url "https://pypi.org/simple"; \
    fi

RUN /opt/superset/venv/bin/pip install --upgrade pip setuptools wheel

ARG SUPERSET_VERSION
# Pin marshmallow<4 due to compatibility issue with Superset 4.0
RUN /opt/superset/venv/bin/pip install \
    "marshmallow<4" \
    "apache-superset[postgres]==${SUPERSET_VERSION}" gunicorn gevent

# Superset config
COPY config/superset_config.py /opt/superset/config/superset_config.py

# Initialize Superset (db migrations, admin user)
COPY scripts/init-superset.sh /tmp/
RUN chmod +x /tmp/init-superset.sh && /tmp/init-superset.sh && rm /tmp/init-superset.sh

# ===== Metabase =====
ARG METABASE_VERSION
RUN mkdir -p /opt/metabase \
    && curl -fsSL -o /opt/metabase/metabase.jar \
       "https://downloads.metabase.com/v${METABASE_VERSION}/metabase.jar"

# ===== AFFiNE =====
ARG AFFINE_VERSION
RUN mkdir -p /opt/affine \
    && curl -fsSL "https://github.com/kingfadzi/AFFiNE/releases/download/v${AFFINE_VERSION}/affine-${AFFINE_VERSION}-linux-x64.tar.gz" \
    | tar -xzf - -C /opt/affine

# Run AFFiNE install.sh (migrations, admin user)
COPY scripts/init-affine.sh /tmp/
RUN chmod +x /tmp/init-affine.sh && /tmp/init-affine.sh && rm /tmp/init-affine.sh

# ===== Claude Code =====
RUN npm install -g @anthropic-ai/claude-code

# ===== User =====
ARG DEFAULT_USER
RUN useradd -m -s /bin/bash ${DEFAULT_USER} \
    && echo "${DEFAULT_USER}:password" | chpasswd \
    && echo "${DEFAULT_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEFAULT_USER} \
    && chmod 0440 /etc/sudoers.d/${DEFAULT_USER}

# ===== Manifest (for backup scripts) =====
ARG BACKUP_DIR
RUN echo "DISTRO_NAME=wsl-${PROFILE}" > /etc/wsl-manifest \
    && echo "BACKUP_DIR=${BACKUP_DIR}" >> /etc/wsl-manifest \
    && echo "PG_PORT=5432" >> /etc/wsl-manifest \
    && echo 'DATABASES="superset metabase affine"' >> /etc/wsl-manifest \
    && echo "RETENTION_DAYS=7" >> /etc/wsl-manifest

# ===== Systemd services =====
COPY config/systemd/superset-web.service /etc/systemd/system/
COPY config/systemd/superset-worker.service /etc/systemd/system/
COPY config/systemd/metabase.service /etc/systemd/system/
COPY config/systemd/affine.service /etc/systemd/system/

# ===== Backup/restore scripts =====
COPY scripts/backup_postgres.sh /usr/local/bin/
COPY scripts/restore_postgres.sh /usr/local/bin/

# ===== AFFiNE start script =====
COPY scripts/start-affine.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/*.sh

# ===== Cron for backups =====
RUN echo "0 3 * * * root /usr/local/bin/backup_postgres.sh --all --yes" > /etc/cron.d/postgresql-backup \
    && chmod 644 /etc/cron.d/postgresql-backup

# ===== Enable services for systemd =====
# Can't use systemctl in Docker build, so create symlinks directly
RUN mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -sf /usr/lib/systemd/system/postgresql.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /usr/lib/systemd/system/redis.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /usr/lib/systemd/system/crond.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/superset-web.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/superset-worker.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/metabase.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/affine.service /etc/systemd/system/multi-user.target.wants/

# Default user for WSL
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}
