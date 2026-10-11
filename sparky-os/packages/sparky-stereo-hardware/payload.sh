#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
set -euo pipefail
install -Dm755 "$HERE/bin/sparky-stereo-hardware" "$D/usr/bin/sparky-stereo-hardware"
mkdir -p "$D/usr/lib/sparky-stereo-hardware" "$D/usr/share/sparky/sparky-stereo-hardware"
install -m644 "$HERE"/lib/* "$D/usr/lib/sparky-stereo-hardware/"
install -m644 "$HERE"/lang/* "$HERE/share/nvidia-open.ids" "$HERE/share/network-ids.tsv" "$HERE/share/nvidia-open-source.txt" "$HERE/share/cuda-key.sh" "$HERE/share/rig-devices.json" "$D/usr/share/sparky/sparky-stereo-hardware/"
install -Dm644 "$HERE/share/sparky-stereo-hardware.desktop" "$D/usr/share/applications/sparky-stereo-hardware.desktop"
install -Dm644 "$HERE/share/org.sparky-stereo-hardware.policy" "$D/usr/share/polkit-1/actions/org.sparky-stereo-hardware.policy"
