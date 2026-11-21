#!/bin/bash
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
job=/work/package-build15/displayxr-problem
mkdir -p "$job"
cp /work/package-source15/displayxr-problem/displayxr-runtime_2.66.3-1+stereo3d10+lc1.dsc /work/package-source15/displayxr-problem/displayxr-runtime_2.66.3-1+stereo3d10+lc1.debian.tar.xz /work/source-inputs/displayxr/displayxr-runtime_2.66.3.orig*.tar.xz "$job/"
cd "$job"
if [ ! -d source ]; then dpkg-source -x displayxr-runtime_2.66.3-1+stereo3d10+lc1.dsc source; fi
cd source
if [ "${SD762_PHASE:-build}" = compile ]; then
 debian/rules execute_before_dh_auto_configure
 DH_OPTIONS="--buildsystem=cmake+ninja --builddirectory=obj-x86_64-linux-gnu" debian/rules override_dh_auto_configure
 dh_auto_build --buildsystem=cmake+ninja --builddirectory=obj-x86_64-linux-gnu
elif [ "${SD762_PHASE:-build}" = build ]; then
 dpkg-buildpackage -Tbuild -us -uc -j4
else
 : "${SPARKY_LC_ARCHIVE_CONFIG:?}" "${SPARKY_LC_SCRATCH:?}" "${SPARKY_LC_PREVIOUS_DIR:?}"
 dpkg-buildpackage -b -nc -us -uc -j4
 PYTHONPATH=/lane/src/sparky-stereo-os-build/sparky-os python3 -m lean.release check-debs "$job/"*.deb
fi
