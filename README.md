# WSL Development Environment

A Dockerfile-based WSL environment with pre-configured development tools and applications.

## Overview

This project uses Docker as a **build tool only** (not at runtime) to create a complete WSL image with:
- PostgreSQL 15, Redis 7
- Python 3.11, Node.js 22, Java 21
- Apache Superset (BI dashboard)
- Metabase (BI tool)
- AFFiNE (knowledge base)
- Claude Code CLI

## Profiles

Two build profiles are available for different network environments:

| Profile | Use Case | Network |
|---------|----------|---------|
| `vpn`   | Laptop with Zscaler | Public DNS (8.8.8.8), Zscaler certs |
| `lan`   | VDI on corporate LAN | Corporate DNS, no Zscaler certs |

## Quick Start

### Prerequisites

- Docker (for building the image)
- Windows with WSL2 enabled

### Build

```bash
# Build for laptop (vpn profile)
docker build -t wsl-vpn \
  --build-arg PROFILE=vpn \
  $(grep -v '^#' profiles/vpn.args | sed 's/^/--build-arg /') \
  .

# Build for VDI (lan profile)
docker build -t wsl-lan \
  --build-arg PROFILE=lan \
  $(grep -v '^#' profiles/lan.args | sed 's/^/--build-arg /') \
  .
```

### Export

```bash
# Export the image as a tarball
docker create --name tmp wsl-vpn
docker export tmp -o wsl-vpn.tar
docker rm tmp

# Or for LAN profile
docker create --name tmp wsl-lan
docker export tmp -o wsl-lan.tar
docker rm tmp
```

### Import to WSL

```powershell
# Import as a new WSL distribution
wsl --import DevEnv C:\WSL\DevEnv wsl-vpn.tar --version 2

# Or for LAN profile
wsl --import DevEnv C:\WSL\DevEnv wsl-lan.tar --version 2
```

### Run

```bash
# Start the WSL distribution
wsl -d DevEnv

# Proxy is auto-loaded from Windows environment variables
# DNS is already configured
# Certificates are already installed (vpn profile)
```

## Directory Structure

```
wsl/
├── Dockerfile              # Main build file
├── .dockerignore           # Files to exclude from build
├── profiles/
│   ├── lan.args            # Build args for VDI (LAN)
│   └── vpn.args            # Build args for laptop (VPN)
├── certs/
│   └── *.cer               # Zscaler certs (vpn profile only)
├── config/
│   ├── wsl.conf            # WSL settings (systemd, automount)
│   ├── superset_config.py  # Superset configuration
│   └── systemd/
│       ├── superset-web.service
│       ├── superset-worker.service
│       ├── metabase.service
│       └── affine.service
├── scripts/
│   ├── proxy.sh            # Windows proxy passthrough
│   ├── init-postgres.sh    # Build-time: create databases
│   ├── init-superset.sh    # Build-time: migrations, admin user
│   ├── init-affine.sh      # Build-time: migrations, admin user
│   ├── backup_postgres.sh  # Runtime: backup databases
│   └── restore_postgres.sh # Runtime: restore databases
└── README.md
```

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `PROFILE` | `vpn` | Profile: `lan` or `vpn` |
| `PYTHON_VERSION` | `3.11` | Python version |
| `NODE_VERSION` | `22` | Node.js version |
| `JAVA_VERSION` | `21` | Java version |
| `SUPERSET_VERSION` | `4.0.0` | Apache Superset version |
| `METABASE_VERSION` | `0.50.21` | Metabase version |
| `AFFINE_VERSION` | `0.16.3` | AFFiNE version |
| `DEFAULT_USER` | `fadzi` | Default Linux user |
| `DNS_SERVERS` | `8.8.8.8 8.8.4.4` | DNS servers (space-separated) |
| `PYPI_INDEX_URL` | (empty) | Corporate PyPI URL |
| `PYPI_TRUSTED_HOST` | (empty) | PyPI trusted host |
| `NPM_REGISTRY` | (empty) | Corporate npm registry |
| `BACKUP_DIR` | `/mnt/f/backups/postgresql` | Backup directory |

## Runtime Configuration

### Proxy

Proxy settings are **not** baked into the image. They are read from Windows environment variables at login:

- `HTTP_PROXY` / `HTTPS_PROXY` - Proxy URL (with credentials)
- `NO_PROXY` - Hosts to bypass proxy

Set these in Windows before starting WSL.

### Services

All services are managed by systemd:

```bash
# Check service status
systemctl status postgresql redis superset-web metabase affine

# Restart a service
sudo systemctl restart superset-web

# View logs
journalctl -u superset-web -f
```

## Application URLs

| Application | URL | Default Credentials |
|-------------|-----|---------------------|
| Superset | http://localhost:8088 | admin / admin |
| Metabase | http://localhost:3000 | (setup on first access) |
| AFFiNE | http://localhost:3010 | admin@localhost / password |

## Backup & Restore

### Backup

```bash
# Backup all databases (for cron)
sudo backup_postgres.sh --all --yes

# Backup specific database
sudo backup_postgres.sh superset

# Interactive mode
sudo backup_postgres.sh
```

### Restore

```bash
# Restore specific database
sudo restore_postgres.sh superset

# Interactive mode
sudo restore_postgres.sh
```

Backups are stored in the configured `BACKUP_DIR` under a host-specific subdirectory.

## Adding CA Certificates

The `certs/` directory supports three types of certificates:

### Corporate CA Bundle (both profiles)

Place `.pem` bundle files for internal root CAs. These are installed for both `lan` and `vpn` profiles:

```bash
cp /path/to/corp-ca-bundle.pem certs/
```

### Zscaler Certificates (vpn profile only)

Place individual `.cer` files for Zscaler. These are converted from DER/PEM format and combined into a single bundle:

```bash
cp /path/to/zscaler-root.cer certs/
cp /path/to/zscaler-intermediate.cer certs/
```

### Java Trust Store (both profiles)

Place `.cacerts` files to replace the Java trust store. This is useful when your org provides a pre-configured Java keystore:

```bash
cp /path/to/corp-java.cacerts certs/
```

Then rebuild:

```bash
docker build -t wsl-vpn --build-arg PROFILE=vpn ...
```

## Customization

### Changing DNS

Edit the DNS_SERVERS in your profile args file:

```bash
# profiles/lan.args
DNS_SERVERS=10.1.1.1 10.1.1.2
```

### Adding Corporate Registries

Edit your profile args file:

```bash
# profiles/vpn.args
PYPI_INDEX_URL=https://nexus.corp/pypi/simple
PYPI_TRUSTED_HOST=nexus.corp
NPM_REGISTRY=https://nexus.corp/npm
```

## Troubleshooting

### DNS not working

Check `/etc/resolv.conf`:
```bash
cat /etc/resolv.conf
```

### Proxy not working

Check if Windows environment variables are set:
```bash
echo $HTTP_PROXY
```

### Service not starting

Check journalctl:
```bash
journalctl -u servicename -n 50
```

### Database connection issues

Verify PostgreSQL is running:
```bash
sudo systemctl status postgresql
sudo -u postgres psql -c "SELECT 1"
```
