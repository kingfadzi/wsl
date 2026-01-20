#!/bin/bash
# Change to home directory if starting from Windows path
# Sourced from /etc/profile.d/03-homedir.sh

[[ $- != *i* ]] && return
[[ "$PWD" == /mnt/* ]] && cd ~
