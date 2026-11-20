#!/bin/bash
# Sparky Stereo OS: build kscreen 4:6.7.4-1+stereo3d15 through Lean Code, inside build-15.sh's container.
# Created by Daniel Ramos (Capitain Jack) 2026/11/15. Copyright 2026 under the GNU GPL3 License.
# /src holds the +15 source prepare-source-15.sh made; /prev the earlier binaries; /repo, /extra, /toolkit as build-15.sh says.
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
job=/work
trap 'chown -R 1000:1000 "$job"' EXIT
: "${SPARKY_LC_ARCHIVE_CONFIG:?the signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?the archive gate scratch directory}"
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
mkdir -p "$job/lc" && cd "$job/lc"
build_args=()
if [ "${SPARKY_KSCREEN_RESUME:-0}" = 1 ]; then
    # the source is the one already unpacked and built: its archives must be the ones it was unpacked from
    sha256sum -c source-closure.sha256
    [ "$(dpkg-parsechangelog -l source/debian/changelog -S Version)" = '4:6.7.4-1+stereo3d15+lc1' ]
    build_args=(-nc)
else
    cp /src/kscreen_6.7.4-1+stereo3d15+lc1.dsc /src/kscreen_6.7.4-1+stereo3d15+lc1.debian.tar.xz /src/kscreen_6.7.4.orig.tar.xz /src/kscreen_6.7.4.orig.tar.xz.asc .
    sha256sum kscreen_6.7.4-1+stereo3d15+lc1.dsc kscreen_6.7.4-1+stereo3d15+lc1.debian.tar.xz kscreen_6.7.4.orig.tar.xz > source-closure.sha256
    dpkg-source -x kscreen_6.7.4-1+stereo3d15+lc1.dsc source > /dev/null
fi
apt-get -y update > "$job/apt-update.log" 2>&1
apt-get -y --no-install-recommends install devscripts quilt bubblewrap > "$job/setup.log" 2>&1
if compgen -G '/extra/*.deb' > /dev/null; then
    apt-get -y --no-install-recommends install /extra/*.deb > "$job/extra-install.log" 2>&1
fi
apt-get -y --no-install-recommends build-dep "$job/lc/source" > "$job/build-dep.log" 2>&1
dpkg-query -W qt6-base-dev libkf6coreaddons-dev plasma-wayland-protocols > "$job/build-versions.txt"
if [ "${SPARKY_KSCREEN_RESUME:-0}" = 1 ]; then
    # Lean Code marks each package's staging tree once and refuses to project it again ("already marked; use a fresh staging
    # tree"): the staging trees and debhelper's per-package logs go, the compiled tree and its build stamp stay
    (cd "$job/lc/source" && for p in $(dh_listpackages); do rm -rf "debian/$p" "debian/$p.debhelper.log" "debian/$p.substvars"; done && rm -rf debian/.debhelper debian/tmp debian/files)
fi
mkdir -p "$SPARKY_LC_SCRATCH"
id builder > /dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder "$job" "$SPARKY_LC_SCRATCH"
cd "$job/lc/source"
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev ${SPARKY_LC_PREVIOUS_SIBLINGS_FILE:+SPARKY_LC_PREVIOUS_SIBLINGS_FILE=$SPARKY_LC_PREVIOUS_SIBLINGS_FILE} \
    SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
    dpkg-buildpackage -b "${build_args[@]}" -us -uc -j4
cd "$job/lc"
PYTHONPATH=/toolkit python3 -m lean.release check-debs "$job/lc/"*.deb
