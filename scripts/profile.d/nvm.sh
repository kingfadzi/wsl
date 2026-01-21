#!/bin/bash
# Source NVM for interactive shells
# Sourced from /etc/profile.d/05-nvm.sh

# Only run for interactive shells
[[ $- != *i* ]] && return

export NVM_DIR="/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
