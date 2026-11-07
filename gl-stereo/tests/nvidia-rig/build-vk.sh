#!/bin/sh
set -e
cd /rig && mkdir -p proto && cd proto
S=wayland-scanner
$S client-header /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml xdg-shell-client-protocol.h
$S private-code /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml xdg-shell-protocol.c
$S client-header /usr/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml xdg-activation-v1-client-protocol.h
$S private-code /usr/share/wayland-protocols/staging/xdg-activation/xdg-activation-v1.xml xdg-activation-v1-protocol.c
P=$(find /usr/share -name plasma-window-management.xml | head -1)
$S client-header $P plasma-window-management-client-protocol.h
$S private-code $P plasma-window-management-protocol.c
cd /rig && gcc -O2 -Iproto -o vk_stereo_wl vk_stereo_wl.c proto/*.c $(pkg-config --cflags --libs wayland-client vulkan) && echo built-vk
