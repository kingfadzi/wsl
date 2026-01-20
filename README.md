# WSL Development Environment

Docker-based WSL2 environment with development tools and BI applications.

## Quick Start

```bash
# Build
./build.sh vpn    # or: ./build.sh lan

# Manual import (if not using build.sh on Windows)
wsl --import DevEnv C:\WSL\DevEnv wsl-vpn.tar --version 2

# Start
wsl -d DevEnv
```

## Profiles

| Profile | DNS | Registries | Certificates |
|---------|-----|------------|--------------|
| `vpn` | Public (8.8.8.8) | Public | Zscaler + Corp CA |
| `lan` | Corporate | Nexus | Corp CA only |

Edit `profiles/vpn.args` or `profiles/lan.args` to customize.

## Build Args

| Arg | Default | Description |
|-----|---------|-------------|
| `PROFILE` | `vpn` | Profile: `vpn` or `lan` |
| `DEFAULT_USER` | `fadzi` | Linux username |
| `DNS_SERVERS` | `8.8.8.8 8.8.4.4` | Space-separated DNS |
| `PYTHON_VERSION` | `3.11` | Python version |
| `NODE_VERSION` | `22` | Node.js version |
| `JAVA_VERSION` | `21` | Java version |
| `GRADLE_VERSION` | `8.5` | Gradle version |
| `PYPI_INDEX_URL` | | Corporate PyPI mirror |
| `NPM_REGISTRY` | | Corporate npm registry |
| `MAVEN_REPO_URL` | | Corporate Maven mirror |
| `GRADLE_REPO_URL` | | Corporate Gradle mirror |
| `GRADLE_DIST_URL` | | Gradle distribution URL |
| `WIN_BASE_DIR` | `/mnt/c/devhome/projects/wsl` | Windows config folder |
| `BACKUP_DIR` | `/mnt/f/backups/postgresql` | Backup location |

## Windows Mounts

Config files are stored on Windows and symlinked into WSL on first login:

| Linux Path | Windows Path |
|------------|--------------|
| `/etc/krb5.conf` | `C:\devhome\projects\wsl\krb5\krb5.conf` |
| `~/.ssh/` | `C:\devhome\projects\wsl\ssh\` |
| `~/.claude/` | `C:\devhome\projects\wsl\claude\` |
| `~/Downloads` | `C:\Users\{username}\Downloads\` |
| `~/f` | `F:\` |

Create the Windows folders before first login:
```powershell
mkdir C:\devhome\projects\wsl\krb5\cache
mkdir C:\devhome\projects\wsl\ssh
mkdir C:\devhome\projects\wsl\claude
```

## Applications

| App | URL | Credentials |
|-----|-----|-------------|
| Superset | http://localhost:8088 | admin / admin |
| Metabase | http://localhost:3000 | (setup on first access) |
| AFFiNE | http://localhost:3010 | admin@localhost / password |

## Services

```bash
systemctl status postgresql redis superset-web metabase affine
sudo systemctl restart superset-web
journalctl -u superset-web -f
```

## Certificates

Place in `certs/` before building:

| Type | Files | Profiles |
|------|-------|----------|
| Corporate CA | `*.pem` | Both |
| Zscaler | `*.cer` | vpn only |
| Java keystore | `*.cacerts` | Both |

## Backup & Restore

```bash
sudo backup_postgres.sh --all --yes   # Backup all DBs
sudo restore_postgres.sh superset     # Restore specific DB
```

Automated daily backup at 3 AM via cron.

## Troubleshooting

| Issue | Check |
|-------|-------|
| DNS not working | `cat /etc/resolv.conf` |
| Proxy not set | `echo $HTTP_PROXY` |
| Service failing | `journalctl -u servicename -n 50` |
| DB connection | `sudo -u postgres psql -c "SELECT 1"` |
| Kerberos ticket | `klist` |
