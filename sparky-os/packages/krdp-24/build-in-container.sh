#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
job=/work/linux/package-24
mkdir -p "$job"
trap 'chown -R 1000:1000 "$job"' EXIT
id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder
cd "$job"
cp /work/linux/source-10-final/krdp_6.7.4-1+stereo3d10.dsc /work/linux/source-10-final/krdp_6.7.4-1+stereo3d10.debian.tar.xz .
cp /repo/pool/main/k/krdp/krdp_6.7.4.orig.tar.xz .
if [ ! -d source ]; then dpkg-source -x krdp_6.7.4-1+stereo3d10.dsc source; fi
printf '[{"uri":"https://deb.debian.org/debian","suite":"forky","components":["main"],"keyring":"/usr/share/keyrings/debian-archive-keyring.gpg"},{"uri":"https://www.deb-multimedia.org","suite":"forky","components":["main","non-free"],"keyring":"/usr/share/keyrings/deb-multimedia-keyring.pgp"},{"uri":"file:/repo","suite":"mashtabba","components":["main"],"keyring":"/repo/sparky-stereo-repo.asc"}]\n' > "$job/archive.json"
export SPARKY_LC_ARCHIVE_CONFIG="$job/archive.json" SPARKY_LC_SCRATCH="$job/link-scratch" SPARKY_LC_PREVIOUS_DIR=/stage
mkdir -p "$SPARKY_LC_SCRATCH"
export SPARKY_LC_SIBLINGS_FILE="$job/siblings.txt"
find /work/linux/kpw-package -maxdepth 1 -name "*.deb" ! -name "*-dbgsym_*" ! -name "*-lc-hr_*" -print | sort > "$SPARKY_LC_SIBLINGS_FILE"
chown -R builder:builder "$job"
cd source
export HOME="$job"
export SPARKY_LC_MIN_FREE_GIB=20 SPARKY_LC_ROOT_MIN_FREE_GIB=20
if [ "${PV24_PHASE:-build}" = build ]; then
 runuser -u builder --preserve-environment -- dpkg-buildpackage -Tbuild -us -uc -j4
 exit 0
fi
[ "$PV24_PHASE" = package ]
runuser -u builder --preserve-environment -- dpkg-buildpackage -b -nc -us -uc -j4
PYTHONPATH=/work/src/sparky-stereo-os-build/sparky-os python3 -m lean.release check-debs "$job/"*.deb
