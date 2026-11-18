#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18. Copyright 2026 under the GNU GPL3 License.
# Inside build-stereo3d26.sh's container: unpack the +26 source, build the architecture-dependent packages through Lean Code, check them.
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=6
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DH_OPTIONS='--builddirectory=build/ --buildsystem=meson'
job=/work
trap 'chown -R 1000:1000 "$job"' EXIT
mkdir -p "$job/lc" && cd "$job/lc"
build_args=()
if [ "${SPARKY_MESA_RESUME:-0}" = 1 ]; then
    # a prepared, compiled tree whose package step stopped: its archives must be the ones it was unpacked from; Lean Code marks
    # each package's staging tree once, so the staging trees and debhelper's logs go, the compiled tree stays
    sha256sum -c source-closure.sha256
    (cd source && for p in $(dh_listpackages -a); do rm -rf "debian/$p" "debian/$p.debhelper.log" "debian/$p.substvars"; done && rm -rf debian/.debhelper debian/tmp debian/files)
    build_args=(-nc)
else
    cp /src/mesa_26.1.6-1+stereo3d26+lc1.dsc /src/mesa_26.1.6-1+stereo3d26+lc1.debian.tar.xz /src/mesa_26.1.6.orig.tar.xz .
    sha256sum mesa_26.1.6-1+stereo3d26+lc1.dsc mesa_26.1.6-1+stereo3d26+lc1.debian.tar.xz mesa_26.1.6.orig.tar.xz > source-closure.sha256
    dpkg-source -x mesa_26.1.6-1+stereo3d26+lc1.dsc source > /dev/null
fi
apt-get -y --no-install-recommends build-dep "$job/lc/source" > "$job/build-dep.log" 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
id builder > /dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder "$job" "$SPARKY_LC_SCRATCH"
cd "$job/lc/source"
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev ${SPARKY_LC_PREVIOUS_SIBLINGS_FILE:+SPARKY_LC_PREVIOUS_SIBLINGS_FILE=$SPARKY_LC_PREVIOUS_SIBLINGS_FILE} \
    SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" HOME=/work/home \
    bash -c 'mkdir -p "$HOME"; dpkg-buildpackage -B -us -uc -j6 "$@"' _ "${build_args[@]}"
cd "$job/lc"
PYTHONPATH=/toolkit python3 -m lean.release check-debs "$job/lc/"*+lc1_*.deb
PYTHONPATH=/toolkit python3 -m lean.release check-link "$job/lc/"*+lc1_*.deb --previous-dir /prev
