#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
set -euo pipefail
install -Dm755 "$HERE/bin/sparky-stereo-hardware" "$D/usr/bin/sparky-stereo-hardware"
mkdir -p "$D/usr/lib/sparky-stereo-hardware" "$D/usr/share/sparky/sparky-stereo-hardware"
install -m644 "$HERE"/lib/* "$D/usr/lib/sparky-stereo-hardware/"
install -m644 "$HERE"/lang/* "$HERE/share/nvidia-open.ids" "$HERE/share/network-ids.tsv" "$HERE/share/nvidia-open-source.txt" "$HERE/share/cuda-key.sh" "$HERE/share/rig-devices.json" "$D/usr/share/sparky/sparky-stereo-hardware/"
install -Dm644 "$HERE/share/sparky-stereo-hardware.desktop" "$D/usr/share/applications/sparky-stereo-hardware.desktop"
install -Dm644 "$HERE/share/org.sparky-stereo-hardware.policy" "$D/usr/share/polkit-1/actions/org.sparky-stereo-hardware.policy"
install -Dm644 "$HERE/share/apt/sparky-stereo-gpu-nvidia" "$D/etc/apt/preferences.d/sparky-stereo-gpu-nvidia"
install -Dm644 "$HERE/share/apt/sparky-stereo-gpu-amd" "$D/etc/apt/preferences.d/sparky-stereo-gpu-amd"
install -Dm755 "$HERE/bin/sparky-stereo-live-gpu-notify" "$D/usr/bin/sparky-stereo-live-gpu-notify"
install -Dm755 "$HERE/share/initramfs/hooks/sparky-stereo-live-gpu" "$D/usr/share/initramfs-tools/hooks/sparky-stereo-live-gpu"
install -Dm755 "$HERE/share/initramfs/scripts/init-top/sparky-stereo-live-gpu" "$D/usr/share/initramfs-tools/scripts/init-top/sparky-stereo-live-gpu"
install -Dm755 "$HERE/share/initramfs/scripts/init-bottom/sparky-stereo-live-gpu" "$D/usr/share/initramfs-tools/scripts/init-bottom/sparky-stereo-live-gpu"
install -Dm644 "$HERE/share/autostart/sparky-stereo-live-gpu.desktop" "$D/etc/xdg/autostart/sparky-stereo-live-gpu.desktop"
install -Dm644 "$HERE/share/plasma-env/sparky-stereo-primary-gpu.sh" "$D/etc/xdg/plasma-workspace/env/sparky-stereo-primary-gpu.sh"
install -Dm755 "$HERE/bin/sparky-stereo-opengl-default" "$D/usr/bin/sparky-stereo-opengl-default"
install -Dm644 "$HERE/share/plasma-env/sparky-stereo-opengl.sh" "$D/etc/xdg/plasma-workspace/env/sparky-stereo-opengl.sh"
install -Dm644 "$HERE/share/systemd/sparky-stereo-opengl-default.service" "$D/usr/lib/systemd/system/sparky-stereo-opengl-default.service"
install -Dm644 "$HERE/share/systemd-user/sparky-stereo-opengl.conf" "$D/usr/lib/systemd/user/plasma-kwin_wayland.service.d/sparky-stereo-opengl.conf"
install -Dm644 "$HERE/share/udev/71-sparky-stereo-opengl-default.rules" "$D/usr/lib/udev/rules.d/71-sparky-stereo-opengl-default.rules"
