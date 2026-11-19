#!/bin/bash
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4
job=/work/linux/ums-package
mkdir -p "$job"
trap 'chown -R 1000:1000 "$job"' EXIT
id builder >/dev/null 2>&1 || useradd --uid 1000 --no-create-home builder
cd "$job"
cp /work/linux/ums-source/ums_15.9.0-1+stereo3d5+lc1.dsc /work/linux/ums-source/ums_15.9.0-1+stereo3d5+lc1.debian.tar.xz /repo/ums_15.9.0.orig.tar.xz .
if [ ! -d source ]; then dpkg-source -x ums_15.9.0-1+stereo3d5+lc1.dsc source; fi
printf '[{"uri":"https://deb.debian.org/debian","suite":"forky","components":["main"],"keyring":"/usr/share/keyrings/debian-archive-keyring.gpg"},{"uri":"https://repo.sparkyos.org","suite":"mashtabba","components":["main"],"keyring":"/repo/repo-key.gpg"}]\n' > "$job/archive.json"
export SPARKY_LC_ARCHIVE_CONFIG="$job/archive.json" SPARKY_LC_SCRATCH="$job/link-scratch" SPARKY_LC_PREVIOUS_DIR=/repo
mkdir -p "$SPARKY_LC_SCRATCH"
chown -R builder:builder "$job"
cd source
export MAVEN_OPTS='-Xmx2g -Duser.home=/work/ums-home'
export COREPACK_HOME=/work/ums-home/.cache/node/corepack
export YARN_GLOBAL_FOLDER=/work/ums-home/.yarn/berry
export YARN_ENABLE_NETWORK=0
export HOME="$job"
export SPARKY_LC_MIN_FREE_GIB=20 SPARKY_LC_ROOT_MIN_FREE_GIB=20
if [ "${PV24_PHASE:-build}" = build ]; then
 runuser -u builder --preserve-environment -- dpkg-buildpackage -Tbuild -us -uc -j4
 exit 0
fi
[ "$PV24_PHASE" = package ]
runuser -u builder --preserve-environment -- dpkg-buildpackage -b -nc -us -uc -j4
PYTHONPATH=/work/src/sparky-stereo-os-build/sparky-os python3 -m lean.release check-debs "$job/"*.deb
