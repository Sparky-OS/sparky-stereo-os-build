#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
job=/work/linux/package-e
mkdir -p "$job"
trap 'chown -R 1000:1000 "$job"' EXIT
id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder
cd "$job"
cp /work/linux/source-9d/krdp_6.7.4-1+stereo3d9.dsc /work/linux/source-9d/krdp_6.7.4-1+stereo3d9.debian.tar.xz .
cp /repo/pool/main/k/krdp/krdp_6.7.4.orig.tar.xz .
dpkg-source -x krdp_6.7.4-1+stereo3d9.dsc source
printf '[{"uri":"https://deb.debian.org/debian","suite":"forky","components":["main"],"keyring":"/usr/share/keyrings/debian-archive-keyring.gpg"},{"uri":"https://www.deb-multimedia.org","suite":"forky","components":["main","non-free"],"keyring":"/usr/share/keyrings/deb-multimedia-keyring.pgp"},{"uri":"file:/repo","suite":"mashtabba","components":["main"],"keyring":"/repo/sparky-stereo-repo.asc"}]\n' > "$job/archive.json"
export SPARKY_LC_ARCHIVE_CONFIG="$job/archive.json" SPARKY_LC_SCRATCH="$job/link-scratch" SPARKY_LC_PREVIOUS_DIR=/repo/pool/main/k/krdp
mkdir -p "$SPARKY_LC_SCRATCH"
chown -R builder:builder "$job"
cd source
export HOME="$job"
runuser -u builder --preserve-environment -- dpkg-buildpackage -b -us -uc -j4
PYTHONPATH=/work/src/sparky-stereo-os-build/sparky-os python3 -m lean.release check-debs "$job/"*.deb
