# WSL Development Environment

Docker-based WSL2 environment with development tools and BI applications.

## Quick Start

```bash
# Build and import (Git Bash on Windows - prompts to import)
./build.sh vpn              # Profile: vpn or lan
./build.sh vpn MyDistro     # Custom distro name (default: DevEnv)

# Build only (Linux/WSL - manual import required)
./build.sh vpn
wsl --import DevEnv C:\WSL\DevEnv wsl-vpn.tar --version 2

# Start
wsl -d DevEnv
```

## Profiles

| Profile | DNS | Registries |
|---------|-----|------------|
| `vpn` | Public (8.8.8.8) | Public |
| `lan` | Corporate | Nexus |

Certificates are loaded at runtime from Windows mount (see [Certificates](#certificates)).

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
| `PYPI_INDEX_URL` | **required** | PyPI mirror URL |
| `PYPI_TRUSTED_HOST` | **required** | PyPI trusted host |
| `NPM_REGISTRY` | **required** | npm registry URL |
| `MAVEN_REPO_URL` | **required** | Maven mirror URL |
| `GRADLE_REPO_URL` | **required** | Gradle mirror URL |
| `GRADLE_DIST_URL` | **required** | Gradle distribution URL |
| `WIN_BASE_DIR` | `/mnt/c/devhome/projects/wsl` | Windows config folder |
| `BACKUP_DIR` | `/mnt/f/backups/postgresql` | Backup location |

## Windows Mounts

Config files are stored on Windows and symlinked into WSL on first login. Missing directories are created automatically.

| Linux Path | Windows Path |
|------------|--------------|
| `/etc/krb5.conf` | `C:\devhome\projects\wsl\krb5\krb5.conf` |
| `/etc/odbc.ini` | `C:\devhome\projects\wsl\odbc\odbc.ini` |
| `/etc/odbcinst.ini` | `C:\devhome\projects\wsl\odbc\odbcinst.ini` |
| `/opt/wsl-certs` | `C:\devhome\projects\wsl\certs\` |
| `/opt/wsl-secrets` | `C:\devhome\projects\wsl\secrets\` |
| `~/.ssh/` | `C:\devhome\projects\wsl\ssh\` |
| `~/.claude/` | `C:\devhome\projects\wsl\claude\` |
| `~/.m2/` | `C:\devhome\projects\wsl\m2\` |
| `~/.gradle/` | `C:\devhome\projects\wsl\gradle\` |
| `~/.npm/` | `C:\devhome\projects\wsl\npm\` |
| `~/.cache/pip/` | `C:\devhome\projects\wsl\pip-cache\` |
| `~/Downloads` | `C:\Users\{username}\Downloads\` |
| `~/f` | `F:\` |

For certificates and Kerberos, create these manually with required files:
```powershell
mkdir C:\devhome\projects\wsl\certs\ca
mkdir C:\devhome\projects\wsl\certs\java
mkdir C:\devhome\projects\wsl\krb5\cache
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

Certificates are loaded from Windows mount on login:

```
C:\devhome\projects\wsl\certs\
├── ca\
│   ├── corporate-ca.pem    # Copied directly
│   └── zscaler.cer         # Converted to PEM
└── java\
    └── cacerts             # Replaces Java keystore
```

Drop any `.pem`, `.crt`, or `.cer` into `ca\` and it will be installed on next login.

## Environment Variables

Environment variables are loaded from Windows mount on login.

Create `C:\devhome\projects\wsl\secrets\profile.env`:

```bash
# Jira
JIRA_API_TOKEN=your-token

# GitLab
GITLAB_TOKEN=your-token

# SonarQube
SONAR_TOKEN=your-token

# Confluence
CONFLUENCE_API_TOKEN=your-token

# Claude Code
ANTHROPIC_API_KEY=your-key
```

All variables are exported automatically on login. Verify with `env | grep YOUR_VAR`.

## Kerberos

The environment uses a shared Kerberos ticket cache on Windows:

```
KRB5CCNAME=/mnt/c/devhome/projects/wsl/krb5/cache/krb5cc
```

**Using Git Bash to obtain tickets:**

```bash
# In Git Bash (Windows)
export KRB5CCNAME=/c/devhome/projects/wsl/krb5/cache/krb5cc
kinit your_principal@REALM

# In WSL - ticket is already available
klist
```

Ensure `C:\devhome\projects\wsl\krb5\krb5.conf` contains your realm configuration.

## Backup & Restore

```bash
# Local (peer auth)
sudo backup-postgres.sh superset
sudo backup-postgres.sh --all --yes

# Remote (password auth - set PGPASSWORD or use ~/.pgpass)
sudo backup-postgres.sh -h remotehost -U dbuser superset
sudo restore-postgres.sh -h remotehost -U dbuser superset

# Restore from specific file (full path or filename)
sudo restore-postgres.sh superset /path/to/backup.dump
sudo restore-postgres.sh superset superset_20260120.dump
```

Backups are stored in `{BACKUP_DIR}/{hostname}-{distro}/`. Automated daily backup at 3 AM via cron with 7-day retention.

## Troubleshooting

| Issue | Check |
|-------|-------|
| DNS not working | `cat /etc/resolv.conf` |
| Proxy not set | `echo $HTTP_PROXY` |
| Service failing | `journalctl -u servicename -n 50` |
| DB connection | `sudo -u postgres psql -c "SELECT 1"` |
| Kerberos ticket | `klist` |
