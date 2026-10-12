#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/12
set -euo pipefail
if ((EUID != 0)); then echo 'Run as root.'; exit 1; fi
if [[ ${1:-} == uninstall ]]; then
	DEBIAN_FRONTEND=noninteractive apt-get -y remove sparky-stereo-cec
else
	: "${OUT:?Set OUT to the package directory}"
	DEBIAN_FRONTEND=noninteractive apt-get -y install "$OUT/sparky-stereo-cec_0.1.2_$(dpkg --print-architecture).deb"
fi
