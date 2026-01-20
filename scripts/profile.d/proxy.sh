# Proxy passthrough from Windows environment variables
# Installed to: /etc/profile.d/proxy.sh
# Sourced at login - reads Windows env vars and exports them to Linux

# Only run if we're in WSL (check for Windows interop)
if [[ -x /mnt/c/Windows/System32/cmd.exe ]]; then
    # Get HTTP_PROXY from Windows
    WIN_PROXY=$(/mnt/c/Windows/System32/cmd.exe /c "echo %HTTP_PROXY%" 2>/dev/null | tr -d '\r\n')
    if [[ "$WIN_PROXY" != "%HTTP_PROXY%" && -n "$WIN_PROXY" ]]; then
        export HTTP_PROXY="$WIN_PROXY"
        export HTTPS_PROXY="$WIN_PROXY"
        export http_proxy="$WIN_PROXY"
        export https_proxy="$WIN_PROXY"
    fi

    # Get NO_PROXY from Windows
    WIN_NO_PROXY=$(/mnt/c/Windows/System32/cmd.exe /c "echo %NO_PROXY%" 2>/dev/null | tr -d '\r\n')
    if [[ "$WIN_NO_PROXY" != "%NO_PROXY%" && -n "$WIN_NO_PROXY" ]]; then
        export NO_PROXY="$WIN_NO_PROXY"
        export no_proxy="$WIN_NO_PROXY"
    fi
fi
