#!/bin/bash
# Load API keys from Windows environment variables
# Sourced from /etc/profile.d/04-secrets.sh

# Only run if we're in WSL (check for Windows interop)
if [[ ! -x /mnt/c/Windows/System32/cmd.exe ]]; then
    return 2>/dev/null || exit 0
fi

# Helper: read Windows env var and export if set
import_win_env() {
    local var="$1"
    local val
    val=$(/mnt/c/Windows/System32/cmd.exe /c "echo %${var}%" 2>/dev/null | tr -d '\r\n')
    if [[ "$val" != "%${var}%" && -n "$val" ]]; then
        export "$var"="$val"
    fi
}

# Import API keys from Windows
import_win_env "ANTHROPIC_API_KEY"
import_win_env "OPENAI_API_KEY"
import_win_env "JIRA_API_TOKEN"
import_win_env "GITLAB_API_TOKEN"
import_win_env "CONFLUENCE_API_TOKEN"
import_win_env "BITBUCKET_API_TOKEN"
import_win_env "SONARQUBE_API_TOKEN"
