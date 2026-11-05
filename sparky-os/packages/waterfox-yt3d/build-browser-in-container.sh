#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build-browser.sh starts it. /work: job folder; /in: the published pool folder;
# /patches: browser/ of this recipe; /browser-toolchains: the compiler bundle.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=${BROWSER_JOBS:-8}
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
OLD=6.7.5-0+stereo3d5+lc1 NEW=6.7.5-0+stereo3d7 COMMIT=81fecb57fbd546be8ed75e082d62210a7ad75833 OLDCOMMIT=b1d115f8d3070a81f3e231acb86cc446656581fd
cd /work && mkdir plain && cd plain
cp /in/sparky-stereo-browser_6.7.5.orig.tar.xz "/in/sparky-stereo-browser_$OLD.dsc" "/in/sparky-stereo-browser_$OLD.debian.tar.xz" .
sha256sum sparky-stereo-browser_6.7.5.orig.tar.xz | tee /work/orig.sha256
# 1. The new source package: the published source, the series' patches, the new debian/ entries; dpkg-source -b.
dpkg-source -x "sparky-stereo-browser_$OLD.dsc" src >/dev/null
cd src
mkdir -p debian/patches
cp /patches/0001-*.patch /patches/0002-*.patch /patches/0003-*.patch /patches/0004-*.patch debian/patches/
ls /patches/0001-*.patch /patches/0002-*.patch /patches/0003-*.patch /patches/0004-*.patch | xargs -n1 basename > debian/patches/series
python3 - <<'PY'
import email.utils
top = open('/patches/changelog7.top').read().replace('@DEBVERSION@', '6.7.5-0+stereo3d7').replace('@DATE@', email.utils.formatdate(localtime=False))
top += open('/patches/changelog.top').read().replace('@DEBVERSION@', '6.7.5-0+stereo3d6').replace('@DATE@', email.utils.formatdate(localtime=False))
lc = ('sparky-stereo-browser (6.7.5-0+stereo3d7+lc1) UNRELEASED; urgency=medium\n\n'
      '  * Apply verified native Lean Code before compilation and qualified lc1\n'
      '    payload assembly; retain exact authored source and HR companions.\n\n'
      ' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=False) + '\n\n')
old = open('debian/changelog').read()
open('debian/changelog', 'w').write(lc + top + old[old.index('sparky-stereo-browser (6.7.5-0+stereo3d5) unstable'):])
PY
grep -q 'libstereo-policy1 (>= 1.4.0)' debian/control
sed -i 's/libstereo-policy1 (>= 1.4.0)/libstereo-policy1 (>= 1.15.0)/' debian/control
# the nine languages of the edition (German added)
grep -q -- '--locales en-US pl pt-BR fr ja ko zh-CN zh-TW' debian/build.sh
sed -i 's/--locales en-US pl pt-BR fr ja ko zh-CN zh-TW/--locales en-US pl pt-BR fr de ja ko zh-CN zh-TW/' debian/build.sh
grep -q "^MOZ_SOURCE_CHANGESET=$OLDCOMMIT\$" debian/browser-build.env
sed -i "s/^MOZ_SOURCE_CHANGESET=.*/MOZ_SOURCE_CHANGESET=$COMMIT/" debian/browser-build.env
grep -q "\"browser_commit\": \"$OLDCOMMIT\"" debian/cargo-baseline.json
sed -i "s/\"browser_commit\": \"$OLDCOMMIT\"/\"browser_commit\": \"$COMMIT\"/" debian/cargo-baseline.json
cd ..
dpkg-source -b src
rm -rf src
sha256sum -c /work/orig.sha256
ls -la
# 2. The build, from the new source package.
mkdir -p /work/build && cd /work/build
cp /work/plain/sparky-stereo-browser_6.7.5.orig.tar.xz /work/plain/sparky-stereo-browser_$NEW+lc1.* .
dpkg-source -x "sparky-stereo-browser_$NEW+lc1.dsc" source >/dev/null
test "$(cat source/SOURCE.edition.json | python3 -c 'import json,sys;print(json.load(sys.stdin)["browser_commit"])')" = "$COMMIT"
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/build/source >/work/build-dep.log 2>&1
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd source
sed -i "s/^mk_add_options MOZ_PARALLEL_BUILD=.*/mk_add_options MOZ_PARALLEL_BUILD=${BROWSER_JOBS:-8}/" debian/mozconfig
runuser -u builder -- env SPARKY_BROWSER_TOOLCHAIN_ROOT=/browser-toolchains dpkg-buildpackage -us -uc -b -j${BROWSER_JOBS:-8}
cp .sparky-lc/source.json /work/native-source.json
cd /work/build
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/build/*+lc1_*.deb
