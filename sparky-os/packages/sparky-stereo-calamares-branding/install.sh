#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/14
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/14
set -euo pipefail
((EUID == 0)) || { echo 'Run as root'; exit 1; }
if [[ ${1:-install} == uninstall ]]; then
	DEBIAN_FRONTEND=noninteractive apt-get -y purge sparky-stereo-calamares-branding
else
	: "${OUT:?Set OUT to the directory containing the built package}"
	DEBIAN_FRONTEND=noninteractive apt-get -y install "$OUT"/sparky-stereo-calamares-branding_*_all.deb
fi
