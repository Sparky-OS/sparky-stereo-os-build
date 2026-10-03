#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
((EUID == 0)) || { echo 'Run as root'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
if [[ ${1:-install} == uninstall ]]; then
	apt-get -y purge xpadneo-dkms
else
	HERE=$(cd "$(dirname "$0")" && pwd)
	OUT=${OUT:?Set OUT to the directory containing the built packages}
	apt-get -y install "$OUT/xpadneo-dkms_0.1.0_all.deb"
fi
