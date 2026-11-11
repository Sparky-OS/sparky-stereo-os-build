#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build-browser.sh starts it. /work: job folder; /in: the published pool folder;
# /patches: browser/ of this recipe; /browser-toolchains: the compiler bundle.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=${BROWSER_JOBS:-8}
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
OLD=6.7.5-0+stereo3d13+lc1 NEW=6.7.5-0+stereo3d14 COMMIT=ad682bee402517c1e534dfe259e8b345bba6af32 OLDCOMMIT=6be1abb34e71b4352957a55f2db03c76d0d0c83d
if [ -z "${BROWSER_RESUME:-}" ]; then
cd /work && mkdir plain && cd plain
cp /in/sparky-stereo-browser_6.7.5.orig.tar.xz "/in/sparky-stereo-browser_$OLD.dsc" "/in/sparky-stereo-browser_$OLD.debian.tar.xz" .
sha256sum sparky-stereo-browser_6.7.5.orig.tar.xz | tee /work/orig.sha256
# 1. The new source package: the published source, the series' patches, the new debian/ entries; dpkg-source -b.
dpkg-source -x "sparky-stereo-browser_$OLD.dsc" src >/dev/null
cd src
mkdir -p debian/patches
cp /patches/0013-*.patch /patches/0014-*.patch /patches/0015-*.patch /patches/0016-*.patch debian/patches/
ls /patches/0013-*.patch /patches/0014-*.patch /patches/0015-*.patch /patches/0016-*.patch | xargs -n1 basename >> debian/patches/series
python3 - <<'PY'
import os
top = open('/patches/changelog14.top').read().replace('@DEBVERSION@', '6.7.5-0+stereo3d14').replace('@DATE@', os.environ['SOURCE_DATE_RFC2822'])
lc = ('sparky-stereo-browser (6.7.5-0+stereo3d14+lc1) UNRELEASED; urgency=medium\n\n'
      '  * Apply verified native Lean Code before compilation and qualified lc1\n'
      '    payload assembly; retain exact authored source and HR companions.\n\n'
      ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n')
old = open('debian/changelog').read()
open('debian/changelog', 'w').write(lc + top + old[old.index('sparky-stereo-browser (6.7.5-0+stereo3d13) unstable'):])
PY
# The package's languages: the nine of the edition and the four Spanish locales (Spanish is the tenth required language; Mozilla's
# locales carry a territory, and ORDER 473u round 3b gives the same Spanish text to all four).
grep -q -- '--locales en-US pl pt-BR fr de ja ko zh-CN zh-TW$' debian/build.sh
sed -i 's/--locales en-US pl pt-BR fr de ja ko zh-CN zh-TW$/--locales en-US pl pt-BR fr de ja ko zh-CN zh-TW es-ES es-MX es-AR es-CL/' debian/build.sh
grep -q "^MOZ_SOURCE_CHANGESET=$OLDCOMMIT\$" debian/browser-build.env
sed -i "s/^MOZ_SOURCE_CHANGESET=.*/MOZ_SOURCE_CHANGESET=$COMMIT/" debian/browser-build.env
# The build ID is how a profile learns that its cached interface is old: the same ID over a new package kept the interface of the
# first build, and menus added later never appeared. Every release gets its own, dated by the recipe, always later than the one before.
grep -q '^MOZ_BUILD_DATE=' debian/browser-build.env
sed -i "s/^MOZ_BUILD_DATE=.*/MOZ_BUILD_DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d%H%M%S)/" debian/browser-build.env
grep -q "\"browser_commit\": \"$OLDCOMMIT\"" debian/cargo-baseline.json
sed -i "s/\"browser_commit\": \"$OLDCOMMIT\"/\"browser_commit\": \"$COMMIT\"/" debian/cargo-baseline.json
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" src
dpkg-source -b src
rm -rf src
sha256sum -c /work/orig.sha256
ls -la
# 2. The build, from the new source package.
mkdir -p /work/build && cd /work/build
cp /work/plain/sparky-stereo-browser_6.7.5.orig.tar.xz /work/plain/sparky-stereo-browser_$NEW+lc1.* .
dpkg-source -x "sparky-stereo-browser_$NEW+lc1.dsc" source >/dev/null
test "$(cat source/SOURCE.edition.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["browser_commit"])')" = "$COMMIT"

fi
cd /work/build
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/build/source >/work/build-dep.log 2>&1
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd source
sed -i "s/^mk_add_options MOZ_PARALLEL_BUILD=.*/mk_add_options MOZ_PARALLEL_BUILD=${BROWSER_JOBS:-8}/" debian/mozconfig
runuser -u builder -- env SPARKY_BROWSER_TOOLCHAIN_ROOT=/browser-toolchains dpkg-buildpackage -us -uc -b ${BROWSER_RESUME:+-nc} -j${BROWSER_JOBS:-8}
cp .sparky-lc/source.json /work/native-source.json
cd /work/build
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/build/*+lc1_*.deb
# The link gate (ORDER 414b): the browser's libraries resolve in the public archives and the edition's published tree, with the
# unpublished libstereo-policy1 of /sib as its sibling, and the program starts (LD_BIND_NOW=1, no display).
if [ -d /sib ]; then
    printf '# package\tprogram\targuments\nsparky-stereo-browser\t/usr/lib/sparky-stereo-browser/sparky-stereo-browser-bin\t--version\n' > /work/browser-smoke.tsv
    printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
    apt-get -y update >/work/apt-update-gate.log 2>&1 || true
    apt-get -y --no-install-recommends install bubblewrap >/work/gate-setup.log 2>&1
    mkdir -p /work/link-scratch && chown -R builder:builder /work/link-scratch
    unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
    PYTHONPATH=/toolkit python3 -m lean.release check-link --archive-config "$SPARKY_LC_ARCHIVE_CONFIG" --scratch "$SPARKY_LC_SCRATCH" \
        --siblings-file /sib/siblings.txt --previous-dir /in --smoke /work/browser-smoke.tsv /work/build/sparky-stereo-browser_*+lc1_amd64.deb 2>&1 | tee /work/link-gate.log
fi
