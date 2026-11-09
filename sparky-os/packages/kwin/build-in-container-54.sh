#!/bin/bash
# Sparky Stereo OS: build kwin 4:6.7.4-2+stereo3d54 through Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22, updated 2026/11/09.
# Copyright 2026 under the GNU GPL3 License
# build.sh supplies /src (published +stereo3d53+lc1 source), /prev (old binaries),
# /repo, /extra, /toolkit and /tools. An optional argument selects the output folder.
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
job=${1:-/work}
mkdir -p "$job"
trap 'chown -R 1000:1000 "$job"' EXIT
: "${SPARKY_LC_ARCHIVE_CONFIG:?the signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?the archive gate scratch directory}"
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
log_suffix=
build_args=()
if [ "${SPARKY_KWIN_RESUME:-0}" = 1 ]; then
    echo 'Resuming the retained +54 package build without cleaning or regenerating source.'
    (cd "$job/lc" && sha256sum -c source-closure.sha256)
    [ "$(dpkg-parsechangelog -l "$job/lc/source/debian/changelog" -S Version)" = '4:6.7.4-2+stereo3d54+lc1' ]
    log_suffix=-resume
    build_args=(-nc -b)
fi
apt-get -y update > "$job/apt-update$log_suffix.log" 2>&1
apt-get -y --no-install-recommends install devscripts quilt bubblewrap > "$job/setup$log_suffix.log" 2>&1
if [ "${SPARKY_KWIN_RESUME:-0}" != 1 ]; then
    bash /tools/prepare-source-54.sh "$job" /src /toolkit
fi
if compgen -G '/extra/*.deb' >/dev/null; then
    apt-get -y --no-install-recommends install /extra/*.deb > "$job/extra-install.log" 2>&1
fi
apt-get -y --no-install-recommends build-dep "$job/lc/source" > "$job/build-dep$log_suffix.log" 2>&1
dpkg-query -W qt6-base-dev libkf6coreaddons-dev plasma-wayland-protocols > "$job/build-versions$log_suffix.txt"
mkdir -p "$SPARKY_LC_SCRATCH"
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder "$job" "$SPARKY_LC_SCRATCH"
cd "$job/lc/source"
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev ${SPARKY_LC_PREVIOUS_SIBLINGS_FILE:+SPARKY_LC_PREVIOUS_SIBLINGS_FILE=$SPARKY_LC_PREVIOUS_SIBLINGS_FILE} ${SPARKY_LC_SIBLINGS_FILE:+SPARKY_LC_SIBLINGS_FILE=$SPARKY_LC_SIBLINGS_FILE} \
    SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
    dpkg-buildpackage "${build_args[@]}" -us -uc -j4
PYTHONPATH=/toolkit python3 -m lean.release check-debs "$job/lc/"*.deb
