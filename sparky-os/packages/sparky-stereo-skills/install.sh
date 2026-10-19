#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
set -euo pipefail
((EUID == 0)) || { echo 'Run as root'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
if [[ ${1:-install} == uninstall ]]; then
	apt-get -y purge sparky-stereo-skills
else
	OUT=${OUT:?Set OUT to the directory containing the built packages}
	HERE=$(cd "$(dirname "$0")" && pwd)
	VERSION=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
	apt-get -y install "$OUT/sparky-stereo-skills_${VERSION}_all.deb"
fi
