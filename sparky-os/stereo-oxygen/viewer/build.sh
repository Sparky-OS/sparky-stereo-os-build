#!/bin/bash
# runs in the container kwin-forky-builddeps:6.7.4 (Daniel's host library versions): builds ./stereo-icon-sheet
set -e
cd "$(dirname "$0")"
X=/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
wayland-scanner client-header $X xdg-shell-client-protocol.h
wayland-scanner private-code $X xdg-shell-protocol.c
V=/usr/share/wayland-protocols/stable/viewporter/viewporter.xml
wayland-scanner client-header $V viewporter-client-protocol.h
wayland-scanner private-code $V viewporter-protocol.c
K=protocols/kde-stereo-content-v1.xml
wayland-scanner client-header $K kde-stereo-content-client-protocol.h
wayland-scanner private-code $K kde-stereo-content-protocol.c
gcc -O2 -Wall -Wextra -o stereo-icon-sheet stereo-icon-sheet.c xdg-shell-protocol.c viewporter-protocol.c kde-stereo-content-protocol.c \
    $(pkg-config --cflags --libs wayland-client wayland-egl egl gl libpng) -lm
strip -s stereo-icon-sheet
ls -l stereo-icon-sheet
