#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build-stereo-layer.sh starts it. /work is the job folder, /repo the signed tree,
# /prev the earlier +lc1 builds, /fork the stereo-layer clone (tag release-1.13.0).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=${JOBS:-8}
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
unset DEB_BUILD_PROFILES # the complete cohort: AV, layer, policy and DIBR
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
git config --global safe.directory '*'
NEWV=1.13.0-1 ORIG=stereo-layer_1.13.0.orig.tar.xz PREFIX=stereo-layer-1.13.0 REV=release-1.13.0
cd /work
# 1. The plain source package: the tag's tree is the orig tarball, its debian/ directory the packaging.
mkdir plain export && cd plain
git -C /fork archive --format=tar --prefix="$PREFIX/" "$REV" | tar -x -C /work/export
cp -a "/work/export/$PREFIX/debian" /work/debian-export
rm -rf "/work/export/$PREFIX/debian"
stamp=$(git -C /fork log -1 --format=%ct "$REV")
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$stamp" -C /work/export -cf - "$PREFIX" | xz -9e > "$ORIG"
tar -xf "$ORIG"
cp -a /work/debian-export "$PREFIX/debian"
test "$(dpkg-parsechangelog -l "$PREFIX/debian/changelog" -S Version)" = "$NEWV"
dpkg-source -b "$PREFIX" >/dev/null
rm -rf "$PREFIX"
ls
# 2. The Lean Code source from it, then the build with the link and start gate against the earlier +lc1 builds.
mkdir -p /work/lc && cd /work/lc
cp /work/plain/* .
dpkg-source -x stereo-layer_"$NEWV".dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$NEWV+lc1" --toolkit /toolkit \
	--preserve-source 'src/*.h' 'Qt moc and QML type registration consume authored declarations.' \
	--preserve-source 'src/*.cpp' 'Qt moc and QML type registration also scan these sources.'
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j${JOBS:-8}
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
# The whole test suite again, by hand, for its exit codes: the build's own dh_auto_test already ran it (a failure stops the build).
cd /work/lc/source/obj-x86_64-linux-gnu
set +e
runuser -u builder -- env QT_QPA_PLATFORM=offscreen ctest --output-on-failure > /work/ctest.log 2>&1
echo "ctest exit code: $?" | tee -a /work/ctest.log
for t in policytest marktest; do
    runuser -u builder -- env QT_QPA_PLATFORM=offscreen ctest --output-on-failure -R "^$t\$" > /work/ctest-$t.log 2>&1
    echo "$t (ctest -R ^$t\$) exit code: $?" | tee -a /work/ctest.log
done
grep -E "tests passed|Passed|Failed|\*\*\*" /work/ctest.log | tee -a /work/build.log
