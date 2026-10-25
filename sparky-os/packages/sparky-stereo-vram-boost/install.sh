#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
set -euo pipefail
if [ "$(id -u)" != 0 ]; then
	echo "Run as root" >&2
	exit 1
fi
if [ "${1:-}" = uninstall ]; then
	apt-get -y remove sparky-stereo-vram-boost
	exit 0
fi
OUT=${OUT:?Set OUT to the folder with the built package}
apt-get -y install "$OUT"/sparky-stereo-vram-boost_*_all.deb
