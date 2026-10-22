#!/bin/bash
# Sparky Stereo OS: vlc-stereo VERSION, the published BASE source package plus ../0NNN-*.patch from FIRST on, built
# with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/10/22
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build-lc.sh starts it. /work is the job folder, /src the published
# sources, /prev the earlier +lc1 builds, /patches the folder of the patch files, /tools this folder.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo ./\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb http://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s && cd s
cp /src/vlc_$BASE.dsc /src/vlc_$BASE.debian.tar.xz /src/vlc_3.0.24.orig.tar.xz /src/vlc_3.0.24.orig.tar.xz.asc .
dpkg-source -x --skip-patches vlc_$BASE.dsc t >/dev/null
cd t
# the new patches go after the last stereo patch of BASE, before the name and the side-by-side patches (the tree is
# unpacked without its patches applied, so that dpkg-source applies the whole series in its new order)
python3 - /patches "$FIRST" <<'SERIES'
import sys, re, shutil
from pathlib import Path
patches, first = Path(sys.argv[1]), int(sys.argv[2])
new = sorted(p for p in patches.glob('0*.patch') if int(p.name[:4]) >= first)
series = Path('debian/patches/series').read_text().splitlines()
last = max(i for i, l in enumerate(series) if re.match(r'3d-\d{4}-', l))
names = ['3d-' + p.name for p in new]
for p, n in zip(new, names):
    if n in series:
        raise SystemExit(n + ' is already in the series')
    shutil.copy(p, 'debian/patches/' + n)
series[last + 1:last + 1] = names
Path('debian/patches/series').write_text('\n'.join(series) + '\n')
print('\n'.join(names))
SERIES
# the changelog entry of VERSION, from the packaging's changelog file
python3 - /tools/changelog "$VERSION" <<'ENTRY' > /work/entry.sh
import sys, shlex
lines, cur = [], None
for l in open(sys.argv[1]):
    l = l.rstrip('\n')
    if l.startswith('== '):
        cur = l[3:]
    elif l and cur == sys.argv[2]:
        lines.append(l)
if not lines:
    raise SystemExit('no changelog entry for ' + sys.argv[2])
print('dch -v %s --distribution testing --force-distribution %s' % (shlex.quote(sys.argv[2]), shlex.quote(lines[0])))
for t in lines[1:]:
    print('dch -a %s' % shlex.quote(t))
ENTRY
. /work/entry.sh
head -40 debian/changelog
cd ..
dpkg-source -b t > /work/source-build.log 2>&1 || { cat /work/source-build.log; exit 1; }
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s/vlc_$VERSION.dsc ../s/vlc_$VERSION.debian.tar.xz ../s/vlc_3.0.24.orig.tar.xz ../s/vlc_3.0.24.orig.tar.xz.asc .
dpkg-source -x vlc_$VERSION.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source $VERSION+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
dpkg -l libchromaprint-dev libavcodec-dev libstereo-policy-dev libstereo-declare-dev libqt5core5t64 libupnp-dev 2>/dev/null | grep '^ii' > /work/build-env.txt || true
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
