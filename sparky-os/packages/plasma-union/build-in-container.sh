#!/bin/bash
# Sparky Stereo OS: plasma-union 6.8.80~git20261022.2163195c-0+stereo3d1, Union master with Debian's packaging and patches/s1-*, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/23
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /fork the Union clone,
# /prev earlier builds, /tools this folder (debian-salsa, patches, the changelog entry).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
UPV=6.8.80~git20261022.2163195c
NEWV=$UPV-0+stereo3d1
ENTRY=/tools/changelog-stereo3d1.txt
if [ -n "${UNION_CONTROL:-}" ]; then
    # the proof rig's control: the same source and packaging without the depth patches, never published
    NEWV=$UPV-0+control1
    ENTRY=/work/changelog-control1.txt
    printf 'plasma-union (%s) unstable; urgency=medium\n\n  * Proof rig control only, never published: Union master 2163195c with the\n    same packaging and none of the depth patches.\n' "$NEWV" > "$ENTRY"
fi
REV=2163195cbe76f5c49e8c636726338924fb6d2d42
PREFIX=union-2163195c
ORIG=plasma-union_$UPV.orig.tar.xz
git config --global safe.directory '*'
mkdir -p /work/plain /work/export && cd /work/plain
git -C /fork archive --format=tar --prefix="$PREFIX/" "$REV" | tar -x -C /work/export
stamp=$(git -C /fork log -1 --format=%ct "$REV")
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$stamp" -C /work/export -cf - "$PREFIX" | xz -9e > "$ORIG"
tar -xf "$ORIG"
cp -a /tools/debian-salsa "$PREFIX/debian"
mkdir -p "$PREFIX/debian/patches"
[ -n "${UNION_CONTROL:-}" ] || for p in /tools/patches/s1-*.patch; do
    cp "$p" "$PREFIX/debian/patches/"
    basename "$p" >> "$PREFIX/debian/patches/series"
done
cd "$PREFIX"
ENTRY="$ENTRY" NEWV="$NEWV" python3 - <<'PACKAGING'
from pathlib import Path
import email.utils, re
p = Path('debian/changelog')
import os
entry = Path(os.environ['ENTRY']).read_text()
assert entry.startswith('plasma-union (' + os.environ['NEWV'] + ') unstable;'), entry[:70]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
c = Path('debian/control')
s = c.read_text()
old = '               libryml-dev,\n'
assert s.count(old) == 1
s = s.replace(old, old + '               libstereo-declare-dev (>= 1.5.0~),\n')
old = '               qt6-base-dev (>= 6.9.0~),\n'
assert s.count(old) == 1
s = s.replace(old, old + '               qt6-base-private-dev (>= 6.9.0~),\n')
old = '               xauth <!nocheck>,\n'
assert s.count(old) == 1
s = s.replace(old, '               dbus <!nocheck>,\n' + old)
c.write_text(s)
r = Path('debian/rules')
s = r.read_text()
old = '\txvfb-run -a -- dh_auto_test\n'
assert s.count(old) == 1
s = s.replace(old, '\txvfb-run -a -- dbus-run-session -- dh_auto_test\n')
# dh_plasmaversionbase takes the Plasma release from the upstream version: 6.8.80 is a pre-release of 6.9 and the
# snapshot suffix is not a number, so it fails; this Union is built against and tested with the edition's Plasma 6.7.
s += '''
override_dh_plasmaversionbase:
\tfor p in $$(dh_listpackages); do echo 'plasma-version:Depends=plasma-version-base-6.7' >> debian/$$p.substvars; done
'''
r.write_text(s)
PACKAGING
head -40 debian/changelog
cd ..
dpkg-source -b "$PREFIX" >/dev/null
rm -rf "$PREFIX" /work/export
ls
mkdir -p /work/lc && cd /work/lc
cp /work/plain/plasma-union_$NEWV.dsc /work/plain/plasma-union_$NEWV.debian.tar.xz /work/plain/$ORIG .
dpkg-source -x "plasma-union_$NEWV.dsc" /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$NEWV+lc1" --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
# libstereo-declare 1.5.0 when it is not in the local repository yet: installed first, so build-dep keeps it
if [ -d /staged ]; then
    apt-get -y --no-install-recommends install /staged/libstereo-declare1_*.deb /staged/libstereo-declare-dev_*.deb >/work/staged.log 2>&1
fi
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
v=$(dpkg-query -W -f='${Version}' libstereo-declare-dev)
dpkg --compare-versions "$v" ge 1.5.0~ || { echo "libstereo-declare-dev $v is older than 1.5.0" >&2; exit 1; }
echo "libstereo-declare-dev $v"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
