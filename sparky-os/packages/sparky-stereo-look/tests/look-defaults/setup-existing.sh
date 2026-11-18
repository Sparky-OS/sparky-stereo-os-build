#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
# This private existing account has a Desktop with a personal file before login.
test -f "$HOME/Desktop/keep.txt"
test -f "$HOME/.config/KDE/Sonnet.conf"
xdg-user-dirs-update
xdg-user-dirs-update --set DESKTOP "$HOME/Desktop"
