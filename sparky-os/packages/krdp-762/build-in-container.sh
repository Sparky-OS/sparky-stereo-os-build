#!/bin/bash
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
job=/work/package-build/krdp
mkdir -p "$job"
cp /work/package-source/krdp/krdp_6.7.4-1+stereo3d12.dsc /work/package-source/krdp/krdp_6.7.4-1+stereo3d12.debian.tar.xz /work/source-inputs/krdp/krdp_6.7.4.orig.tar.xz "$job/"
cd "$job"
if [ ! -d source ]; then dpkg-source -x krdp_6.7.4-1+stereo3d12.dsc source; fi
cd source
if [ "${SD762_PHASE:-build}" = build ]; then
 dpkg-buildpackage -Tbuild -us -uc -j4
else
 : "${SPARKY_LC_ARCHIVE_CONFIG:?}" "${SPARKY_LC_SCRATCH:?}" "${SPARKY_LC_PREVIOUS_DIR:?}"
 dpkg-buildpackage -b -nc -us -uc -j4
 PYTHONPATH=/lane/src/sparky-stereo-os-build/sparky-os python3 -m lean.release check-debs "$job/"*.deb
fi
