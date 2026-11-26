#!/bin/bash
# Sparky Stereo OS: build qt6-base 6.11.2+dfsg-5+stereo3d25 through Lean Code, inside build-25.sh's container (queue row 121).
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# /src holds the +25 source next-source-25.sh made; /prev the +24 binaries; /repo, /extra, /toolkit as build-25.sh says.
# After the packages, the build tree builds and runs tst_qwidgetrepaintmanager (Debian builds no tests): its log is
# /work/unit-test.log and its exit status /work/unit-test.status.
set -euo pipefail
cp /run/host-ca.crt /etc/ssl/certs/ca-certificates.crt
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
job=/work
version=6.11.2+dfsg-5+stereo3d25+lc1
trap 'chown -R 1000:1000 "$job"' EXIT
: "${SPARKY_LC_ARCHIVE_CONFIG:?the signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?the archive gate scratch directory}"
printf 'deb [signed-by=/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cp /repo/sparky-stereo-repo.asc /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
mkdir -p "$job/lc" && cd "$job/lc"
build_args=()
if [ "${SPARKY_QT_RESUME:-0}" = 1 ]; then
    # the source is the one already unpacked and built: its archives must be the ones it was unpacked from
    sha256sum -c source-closure.sha256
    [ "$(dpkg-parsechangelog -l source/debian/changelog -S Version)" = "$version" ]
    build_args=(-nc)
else
    cp "/src/qt6-base_$version.dsc" "/src/qt6-base_$version.debian.tar.xz" /src/qt6-base_6.11.2+dfsg.orig.tar.xz .
    sha256sum "qt6-base_$version.dsc" "qt6-base_$version.debian.tar.xz" qt6-base_6.11.2+dfsg.orig.tar.xz > source-closure.sha256
    dpkg-source -x "qt6-base_$version.dsc" source > /dev/null
fi
apt-get -y update > "$job/apt-update.log" 2>&1
apt-get -y --no-install-recommends install devscripts quilt bubblewrap > "$job/setup.log" 2>&1
if compgen -G '/extra/*.deb' > /dev/null; then
    apt-get -y --no-install-recommends install /extra/*.deb > "$job/extra-install.log" 2>&1
fi
apt-get -y --no-install-recommends build-dep "$job/lc/source" > "$job/build-dep.log" 2>&1
dpkg-query -W libwayland-dev libegl-dev libgl-dev libvulkan-dev > "$job/build-versions.txt"
if [ "${SPARKY_QT_RESUME:-0}" = 1 ]; then
    # Lean Code marks each package's staging tree once and refuses to project it again ("already marked; use a fresh staging
    # tree"): the staging trees and debhelper's per-package logs go, the compiled tree and its build stamp stay
    (cd "$job/lc/source" && for p in $(dh_listpackages); do rm -rf "debian/$p" "debian/$p.debhelper.log" "debian/$p.substvars"; done && rm -rf debian/.debhelper debian/tmp debian/files)
fi
mkdir -p "$SPARKY_LC_SCRATCH"
# an image without a user of uid 1000 makes getent fail, which set -e and pipefail would take as the end of the build
build_user=$(getent passwd 1000 | cut -d: -f1 || true)
if [ -z "$build_user" ]; then
    useradd --create-home --uid 1000 builder
    build_user=builder
fi
chown -R 1000:1000 "$job" "$SPARKY_LC_SCRATCH"
cd "$job/lc/source"
runuser -u "$build_user" -- env SPARKY_LC_PREVIOUS_DIR=/prev ${SPARKY_LC_PREVIOUS_SIBLINGS_FILE:+SPARKY_LC_PREVIOUS_SIBLINGS_FILE=$SPARKY_LC_PREVIOUS_SIBLINGS_FILE} \
    SPARKY_LC_SIBLINGS_FILE="$SPARKY_LC_PREVIOUS_SIBLINGS_FILE" SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
    dpkg-buildpackage -b "${build_args[@]}" -us -uc -j4
cd "$job/lc"
PYTHONPATH=/toolkit python3 -m lean.release check-debs "$job/lc/"*.deb
# the change's own test, in the tree the packages were built from (the packages are already made and checked above)
cd "$job/lc/source/obj-x86_64-linux-gnu"
set +e
runuser -u "$build_user" -- sh -c 'cmake -DQT_BUILD_TESTS=ON -DQT_BUILD_TESTS_BY_DEFAULT=OFF . > /work/unit-test.log 2>&1 &&
    ninja -j4 tst_qwidgetrepaintmanager >> /work/unit-test.log 2>&1 &&
    cd tests/auto/widgets/kernel/qwidgetrepaintmanager &&
    QT_QPA_PLATFORM=offscreen ./tst_qwidgetrepaintmanager paintOncePerEye paintRectsAtTheirDepth >> /work/unit-test.log 2>&1'
echo $? > /work/unit-test.status
set -e
