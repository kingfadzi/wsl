# DevEnv WSL Image
# Development environment with PostgreSQL, Redis, Superset, AFFiNE, Redash
#
# Build: ./build.sh vpn
# Import: wsl --import DevEnv C:\wsl\DevEnv devenv-vpn.tar --version 2
#
# Requires: wsl-base:${PROFILE} to be built first (auto-builds if missing)
#
ARG PROFILE=vpn
FROM wsl-base:${PROFILE}

USER root

# ===== Build args (devenv specific) =====
ARG GRADLE_VERSION=8.5
ARG SUPERSET_VERSION=6.0.0
ARG AFFINE_RELEASE=affine.tar.gz
ARG REDASH_RELEASE=redash.tar.gz
ARG DEFAULT_USER=fadzi
ARG PYPI_INDEX_URL=
ARG PYPI_TRUSTED_HOST=
ARG NPM_REGISTRY=
ARG SASS_BINARY_SITE=
ARG MAVEN_REPO_URL=
ARG GRADLE_REPO_URL=
ARG GRADLE_DIST_URL=
ARG WIN_BASE_DIR=/mnt/c/devhome/projects/wsl
ARG BACKUP_DIR=/mnt/f/backups/postgresql

# ===== Additional packages (devenv specific) =====
RUN dnf install -y --allowerasing \
    findutils \
    cronie \
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

# ===== Gradle binary =====
ARG GRADLE_VERSION
ARG GRADLE_DIST_URL
RUN if [ -n "$GRADLE_DIST_URL" ]; then \
        curl -fL# "${GRADLE_DIST_URL}/gradle-${GRADLE_VERSION}-bin.zip" -o /tmp/gradle.zip && \
        unzip -q /tmp/gradle.zip -d /opt && \
        mv /opt/gradle-${GRADLE_VERSION} /opt/gradle && \
        rm /tmp/gradle.zip; \
    else \
        echo "GRADLE_DIST_URL not set - skipping Gradle"; \
    fi
ENV PATH="$PATH:/opt/gradle/bin"

# ===== Maven settings =====
ARG MAVEN_REPO_URL
COPY config/maven-settings.xml /tmp/maven-settings.xml
RUN if [ -n "$MAVEN_REPO_URL" ]; then \
        mkdir -p /etc/skel/.m2 && \
        sed "s|MAVEN_REPO_URL|$MAVEN_REPO_URL|g" /tmp/maven-settings.xml > /etc/skel/.m2/settings.xml; \
    fi && rm -f /tmp/maven-settings.xml

# ===== Gradle init =====
ARG GRADLE_REPO_URL
COPY config/gradle-init.gradle /tmp/gradle-init.gradle
RUN if [ -n "$GRADLE_REPO_URL" ]; then \
        mkdir -p /etc/skel/.gradle && \
        sed "s|GRADLE_REPO_URL|$GRADLE_REPO_URL|g" /tmp/gradle-init.gradle > /etc/skel/.gradle/init.gradle; \
    fi && rm -f /tmp/gradle-init.gradle

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

# Superset venv configuration
ARG PYPI_INDEX_URL
ARG PYPI_TRUSTED_HOST
RUN if [ -n "$PYPI_INDEX_URL" ]; then \
        /opt/superset/venv/bin/pip config set global.index-url "$PYPI_INDEX_URL" && \
        /opt/superset/venv/bin/pip config set global.trusted-host "$PYPI_TRUSTED_HOST" && \
        /opt/superset/venv/bin/pip config set global.extra-index-url "https://pypi.org/simple"; \
    fi

RUN /opt/superset/venv/bin/pip install --upgrade pip setuptools wheel

ARG SUPERSET_VERSION
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

# Note: Claude Code is now provided by wsl-base image

# ===== Manifest (for backup scripts and mounts) =====
ARG BACKUP_DIR
ARG WIN_BASE_DIR
ARG NVM_NODEJS_ORG_MIRROR
ARG NPM_REGISTRY
ARG SASS_BINARY_SITE
RUN echo "DISTRO_NAME=devenv-${PROFILE}" >> /etc/wsl-manifest \
    && echo "BACKUP_DIR=${BACKUP_DIR}" >> /etc/wsl-manifest \
    && echo "PG_PORT=5432" >> /etc/wsl-manifest \
    && echo 'DATABASES="superset affine redash"' >> /etc/wsl-manifest \
    && echo "RETENTION_DAYS=7" >> /etc/wsl-manifest \
    && echo "SASS_BINARY_SITE=${SASS_BINARY_SITE}" >> /etc/wsl-manifest

# ===== Kerberos environment =====
ARG WIN_BASE_DIR
ENV KRB5CCNAME="${WIN_BASE_DIR}/krb5/cache/krb5cc"

# ===== WSL Configuration (devenv specific) =====
COPY config/wsl.conf /etc/wsl.conf

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

# ===== Profile scripts (devenv-specific, runs after base's 00-05) =====
# Note: mounts.sh and secrets.sh are now in wsl-base
COPY scripts/profile.d/certs.sh /etc/profile.d/06-certs.sh
COPY scripts/profile.d/homedir.sh /etc/profile.d/07-homedir.sh
RUN chmod 644 /etc/profile.d/06-certs.sh /etc/profile.d/07-homedir.sh

# ===== Cron for backups =====
RUN echo "0 3 * * * root /usr/local/bin/backup-postgres.sh --all --yes" > /etc/cron.d/postgresql-backup \
    && chmod 644 /etc/cron.d/postgresql-backup

# ===== Enable services for systemd =====
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
