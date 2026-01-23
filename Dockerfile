FROM almalinux:9

# ===== Build args =====
ARG PROFILE=vpn
ARG PYTHON_VERSION=3.11
ARG JAVA_VERSION=21
ARG NVM_INSTALL_URL=
ARG NVM_NODEJS_ORG_MIRROR=
ARG GRADLE_VERSION=8.5
ARG SUPERSET_VERSION=6.0.0
ARG AFFINE_URL=
ARG REDASH_URL=
ARG DEFAULT_USER=fadzi
ARG DNS_SERVERS="8.8.8.8 8.8.4.4"
ARG PYPI_INDEX_URL=
ARG PYPI_TRUSTED_HOST=
ARG NPM_REGISTRY=
ARG SASS_BINARY_SITE=
ARG TLS_CA_BUNDLE_URL=
ARG MAVEN_REPO_URL=
ARG GRADLE_REPO_URL=
ARG GRADLE_DIST_URL=
ARG WIN_BASE_DIR=/mnt/c/devhome/projects/wsl
ARG BACKUP_DIR=/mnt/f/backups/postgresql

# ===== Enable CRB repo for -devel packages (no-op if unavailable in prod) =====
RUN dnf install -y 'dnf-command(config-manager)' && \
    dnf config-manager --set-enabled crb || true

# ===== Base packages =====
RUN dnf install -y --allowerasing \
    git vim curl wget jq hostname bind-utils \
    iputils net-tools procps-ng findutils \
    sudo passwd cronie gcc gcc-c++ make \
    ca-certificates tar gzip unzip openssl \
    krb5-workstation krb5-devel \
    unixODBC \
    maven \
    && dnf clean all

# ===== SQL Server ODBC driver =====
RUN ACCEPT_EULA=Y dnf install -y msodbcsql18 mssql-tools18 2>/dev/null || { \
        curl -fL# https://packages.microsoft.com/config/rhel/9/prod.repo > /etc/yum.repos.d/mssql-release.repo && \
        ACCEPT_EULA=Y dnf install -y msodbcsql18 mssql-tools18 && \
        rm -f /etc/yum.repos.d/mssql-release.repo; \
    } && dnf clean all
ENV PATH="$PATH:/opt/mssql-tools18/bin"

# ===== WSL config =====
COPY config/wsl.conf /etc/wsl.conf

# ===== DNS (baked in per profile) =====
# Docker mounts /etc/resolv.conf during build, so we write to a staging file
# and copy it on first boot via profile.d script
ARG DNS_SERVERS
RUN for dns in ${DNS_SERVERS}; do echo "nameserver $dns" | tr -d '\r' >> /etc/resolv.conf.wsl; done && \
    echo '#!/bin/bash' > /etc/profile.d/00-dns.sh && \
    echo '# Copy baked DNS config (wsl.conf has generateResolvConf=false)' >> /etc/profile.d/00-dns.sh && \
    echo '[ -f /etc/resolv.conf.wsl ] && sudo cp -f /etc/resolv.conf.wsl /etc/resolv.conf 2>/dev/null' >> /etc/profile.d/00-dns.sh && \
    chmod 644 /etc/profile.d/00-dns.sh

# ===== Proxy passthrough script (reads Windows env vars at login) =====
COPY scripts/profile.d/proxy.sh /etc/profile.d/proxy.sh
RUN chmod 644 /etc/profile.d/proxy.sh

# ===== Runtimes (Python, Java) =====
ARG PYTHON_VERSION
ARG JAVA_VERSION
RUN dnf install -y \
       python${PYTHON_VERSION} python${PYTHON_VERSION}-pip python${PYTHON_VERSION}-devel \
       python3.9 python3.9-devel \
       java-${JAVA_VERSION}-openjdk java-${JAVA_VERSION}-openjdk-devel \
    && dnf clean all

# Set Python alternatives
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1 \
    && alternatives --install /usr/bin/pip pip /usr/bin/pip${PYTHON_VERSION} 1 \
    && alternatives --install /usr/bin/pip3 pip3 /usr/bin/pip${PYTHON_VERSION} 1

# ===== Corporate TLS CA Bundle + Java Cacerts =====
ARG TLS_CA_BUNDLE_URL
RUN if [ -n "$TLS_CA_BUNDLE_URL" ]; then \
        curl -fL# "$TLS_CA_BUNDLE_URL" -o /tmp/certs.zip && \
        unzip -q /tmp/certs.zip -d /tmp/certs && \
        find /tmp/certs -name "tls-ca-bundle.pem" -exec cp {} /etc/pki/ca-trust/source/anchors/ \; && \
        update-ca-trust extract && \
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java) 2>/dev/null)) 2>/dev/null) && \
        if [ -n "$JAVA_HOME" ] && [ -d "$JAVA_HOME/lib/security" ]; then \
            find /tmp/certs -name "cacerts" -exec cp {} $JAVA_HOME/lib/security/cacerts \; ; \
        fi && \
        rm -rf /tmp/certs.zip /tmp/certs && \
        echo "Corporate certificates installed (TLS CA bundle + Java cacerts)"; \
    else \
        echo "WARNING: TLS_CA_BUNDLE_URL not set - using system defaults"; \
    fi

# ===== Package registries =====

# pip (system-wide)
ARG PYPI_INDEX_URL
ARG PYPI_TRUSTED_HOST
RUN mkdir -p /etc && \
    echo "[global]" > /etc/pip.conf && \
    echo "index-url = ${PYPI_INDEX_URL}" >> /etc/pip.conf && \
    echo "trusted-host = ${PYPI_TRUSTED_HOST}" >> /etc/pip.conf

# ===== NVM + Node.js =====
ARG NVM_INSTALL_URL
ARG NVM_NODEJS_ORG_MIRROR
ENV NVM_DIR=/opt/nvm
RUN if [ -z "$NVM_INSTALL_URL" ]; then echo "ERROR: NVM_INSTALL_URL required" && exit 1; fi && \
    if [ -z "$NVM_NODEJS_ORG_MIRROR" ]; then echo "ERROR: NVM_NODEJS_ORG_MIRROR required" && exit 1; fi && \
    mkdir -p $NVM_DIR && \
    curl -fL# "$NVM_INSTALL_URL" -o /tmp/nvm.zip && \
    unzip -q /tmp/nvm.zip -d /tmp/nvm && \
    if [ -f /tmp/nvm/*/install.sh ]; then \
        bash /tmp/nvm/*/install.sh; \
    else \
        cp -r /tmp/nvm/* $NVM_DIR/; \
    fi && \
    rm -rf /tmp/nvm.zip /tmp/nvm && \
    . $NVM_DIR/nvm.sh && \
    export NVM_NODEJS_ORG_MIRROR=$NVM_NODEJS_ORG_MIRROR && \
    export NVM_CURL_OPTIONS="-#" && \
    nvm install --lts && \
    nvm alias default lts/*

# ===== npm/yarn configuration (after Node.js installed) =====
ARG NPM_REGISTRY
ARG SASS_BINARY_SITE
RUN . $NVM_DIR/nvm.sh && \
    npm config set registry "${NPM_REGISTRY}" && \
    npm config set cafile /etc/pki/tls/certs/ca-bundle.crt && \
    npm install -g yarn --no-save && \
    echo "registry=${NPM_REGISTRY}" > /etc/npmrc && \
    echo "cafile=/etc/pki/tls/certs/ca-bundle.crt" >> /etc/npmrc && \
    echo "sass_binary_site=${SASS_BINARY_SITE}" >> /etc/npmrc && \
    echo "registry \"${NPM_REGISTRY}\"" > /etc/yarnrc && \
    echo "cafile \"/etc/pki/tls/certs/ca-bundle.crt\"" >> /etc/yarnrc && \
    echo "sass-binary-site \"${SASS_BINARY_SITE}\"" >> /etc/yarnrc && \
    echo "registry=${NPM_REGISTRY}" > /etc/skel/.npmrc && \
    echo "cafile=/etc/pki/tls/certs/ca-bundle.crt" >> /etc/skel/.npmrc && \
    echo "sass_binary_site=${SASS_BINARY_SITE}" >> /etc/skel/.npmrc

# ===== Gradle binary =====
ARG GRADLE_VERSION
ARG GRADLE_DIST_URL
RUN if [ -z "$GRADLE_DIST_URL" ]; then echo "ERROR: GRADLE_DIST_URL required" && exit 1; fi && \
    curl -fL# "${GRADLE_DIST_URL}/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip && \
    unzip -q /tmp/gradle.zip -d /opt && \
    mv /opt/gradle-${GRADLE_VERSION} /opt/gradle && \
    rm /tmp/gradle.zip
ENV PATH="$PATH:/opt/gradle/bin"

# ===== Maven settings =====
ARG MAVEN_REPO_URL
COPY config/maven-settings.xml /tmp/maven-settings.xml
RUN if [ -z "$MAVEN_REPO_URL" ]; then echo "ERROR: MAVEN_REPO_URL required" && exit 1; fi && \
    mkdir -p /etc/skel/.m2 && \
    sed "s|MAVEN_REPO_URL|$MAVEN_REPO_URL|g" /tmp/maven-settings.xml > /etc/skel/.m2/settings.xml && \
    rm -f /tmp/maven-settings.xml

# ===== Gradle init =====
ARG GRADLE_REPO_URL
COPY config/gradle-init.gradle /tmp/gradle-init.gradle
RUN if [ -z "$GRADLE_REPO_URL" ]; then echo "ERROR: GRADLE_REPO_URL required" && exit 1; fi && \
    mkdir -p /etc/skel/.gradle && \
    sed "s|GRADLE_REPO_URL|$GRADLE_REPO_URL|g" /tmp/gradle-init.gradle > /etc/skel/.gradle/init.gradle && \
    rm -f /tmp/gradle-init.gradle

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
COPY scripts/init/postgres.sh /tmp/init-postgres.sh
RUN chmod +x /tmp/init-postgres.sh && /tmp/init-postgres.sh && rm /tmp/init-postgres.sh

# ===== Superset =====
RUN python3 -m venv /opt/superset/venv

# Superset venv uses public PyPI fallback
ARG PYPI_INDEX_URL
ARG PYPI_TRUSTED_HOST
RUN /opt/superset/venv/bin/pip config set global.index-url "$PYPI_INDEX_URL" && \
    /opt/superset/venv/bin/pip config set global.trusted-host "$PYPI_TRUSTED_HOST" && \
    /opt/superset/venv/bin/pip config set global.extra-index-url "https://pypi.org/simple"

RUN /opt/superset/venv/bin/pip install --upgrade pip setuptools wheel

ARG SUPERSET_VERSION
# Pin marshmallow<4 due to compatibility issue with Superset 4.0
RUN /opt/superset/venv/bin/pip install \
    "marshmallow<4" \
    "apache-superset[postgres]==${SUPERSET_VERSION}" gunicorn gevent \
    pyodbc

# Superset config
COPY config/superset_config.py /opt/superset/config/superset_config.py

# Initialize Superset (db migrations, admin user)
COPY scripts/init/superset.sh /tmp/init-superset.sh
RUN chmod +x /tmp/init-superset.sh && /tmp/init-superset.sh && rm /tmp/init-superset.sh

# ===== AFFiNE =====
ARG AFFINE_RELEASE
COPY binaries/${AFFINE_RELEASE} /tmp/affine.tar.gz
RUN mkdir -p /opt/affine \
    && tar --no-same-owner -xzf /tmp/affine.tar.gz -C /opt/affine \
    && rm /tmp/affine.tar.gz

# Run AFFiNE install.sh (migrations, admin user)
COPY scripts/init/affine.sh /tmp/init-affine.sh
RUN chmod +x /tmp/init-affine.sh && /tmp/init-affine.sh && rm /tmp/init-affine.sh

# ===== Redash =====
ARG REDASH_RELEASE
COPY binaries/${REDASH_RELEASE} /tmp/redash.tar.gz
RUN mkdir -p /opt/redash \
    && tar -xzf /tmp/redash.tar.gz -C /opt/redash \
    && rm /tmp/redash.tar.gz

# Initialize Redash (create .env, init database)
COPY scripts/init/redash.sh /tmp/init-redash.sh
RUN chmod +x /tmp/init-redash.sh && /tmp/init-redash.sh && rm /tmp/init-redash.sh

# ===== Claude Code =====
RUN . $NVM_DIR/nvm.sh && npm install -g @anthropic-ai/claude-code

# ===== User =====
ARG DEFAULT_USER
RUN useradd -m -s /bin/bash ${DEFAULT_USER} \
    && echo "${DEFAULT_USER}:password" | chpasswd \
    && echo "${DEFAULT_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${DEFAULT_USER} \
    && chmod 0440 /etc/sudoers.d/${DEFAULT_USER} \
    && chown -R ${DEFAULT_USER}:${DEFAULT_USER} /opt/nvm

# ===== F: drive mount point (local fallback if network drive unavailable) =====
RUN mkdir -p /mnt/f

# ===== F: drive mount helper =====
COPY scripts/lib/mount-f-drive.sh /usr/local/lib/mount-f-drive.sh
RUN chmod 644 /usr/local/lib/mount-f-drive.sh

# ===== Manifest (for backup scripts and mounts) =====
ARG BACKUP_DIR
ARG WIN_BASE_DIR
ARG NVM_NODEJS_ORG_MIRROR
ARG NPM_REGISTRY
ARG SASS_BINARY_SITE
RUN echo "DISTRO_NAME=wsl-${PROFILE}" > /etc/wsl-manifest \
    && echo "BACKUP_DIR=${BACKUP_DIR}" >> /etc/wsl-manifest \
    && echo "WIN_BASE_DIR=${WIN_BASE_DIR}" >> /etc/wsl-manifest \
    && echo "PG_PORT=5432" >> /etc/wsl-manifest \
    && echo 'DATABASES="superset affine redash"' >> /etc/wsl-manifest \
    && echo "RETENTION_DAYS=7" >> /etc/wsl-manifest \
    && echo "NVM_DIR=/opt/nvm" >> /etc/wsl-manifest \
    && echo "NVM_NODEJS_ORG_MIRROR=${NVM_NODEJS_ORG_MIRROR}" >> /etc/wsl-manifest \
    && echo "NPM_REGISTRY=${NPM_REGISTRY}" >> /etc/wsl-manifest \
    && echo "SASS_BINARY_SITE=${SASS_BINARY_SITE}" >> /etc/wsl-manifest

# ===== Kerberos environment =====
ARG WIN_BASE_DIR
ENV KRB5CCNAME="${WIN_BASE_DIR}/krb5/cache/krb5cc"

# ===== Systemd services =====
COPY config/systemd/superset-web.service /etc/systemd/system/
COPY config/systemd/superset-worker.service /etc/systemd/system/
COPY config/systemd/affine.service /etc/systemd/system/
COPY config/systemd/redash-server.service /etc/systemd/system/
COPY config/systemd/redash-worker.service /etc/systemd/system/
COPY config/systemd/redash-scheduler.service /etc/systemd/system/

# ===== Backup/restore scripts =====
COPY scripts/bin/backup-postgres.sh /usr/local/bin/
COPY scripts/bin/restore-postgres.sh /usr/local/bin/

# ===== AFFiNE start script =====
COPY scripts/bin/start-affine.sh /usr/local/bin/

RUN chmod +x /usr/local/bin/*.sh

# ===== Windows mounts setup (symlinks on first login) =====
COPY scripts/profile.d/mounts.sh /etc/profile.d/01-mounts.sh
COPY scripts/profile.d/certs.sh /etc/profile.d/02-certs.sh
COPY scripts/profile.d/homedir.sh /etc/profile.d/03-homedir.sh
COPY scripts/profile.d/secrets.sh /etc/profile.d/04-secrets.sh
COPY scripts/profile.d/nvm.sh /etc/profile.d/05-nvm.sh
COPY scripts/profile.d/npm.sh /etc/profile.d/06-npm.sh
RUN chmod 644 /etc/profile.d/01-mounts.sh /etc/profile.d/02-certs.sh /etc/profile.d/03-homedir.sh /etc/profile.d/04-secrets.sh /etc/profile.d/05-nvm.sh /etc/profile.d/06-npm.sh

# ===== Cron for backups =====
RUN echo "0 3 * * * root /usr/local/bin/backup-postgres.sh --all --yes" > /etc/cron.d/postgresql-backup \
    && chmod 644 /etc/cron.d/postgresql-backup

# ===== Enable services for systemd =====
# Can't use systemctl in Docker build, so create symlinks directly
RUN mkdir -p /etc/systemd/system/multi-user.target.wants && \
    ln -sf /usr/lib/systemd/system/postgresql.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /usr/lib/systemd/system/redis.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /usr/lib/systemd/system/crond.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/superset-web.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/superset-worker.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/affine.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/redash-server.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/redash-worker.service /etc/systemd/system/multi-user.target.wants/ && \
    ln -sf /etc/systemd/system/redash-scheduler.service /etc/systemd/system/multi-user.target.wants/

# Default user for WSL
USER ${DEFAULT_USER}
WORKDIR /home/${DEFAULT_USER}
