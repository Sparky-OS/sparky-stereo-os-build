#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build-plasmatube.sh starts it. /work: job folder; /src: the plain +stereo3d4 source;
# /extra: libstereo-policy 1.13.0-1+lc1; /repo: the signed tree; /prev: the earlier +lc1 builds; /recipe: patch and changelog entry.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=${JOBS:-8}
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
BASE=plasmatube_26.08.1-1+stereo3d4 NEWV=26.08.1-1+stereo3d5
cd /work && mkdir plain && cd plain
cp /src/$BASE.dsc /src/$BASE.debian.tar.xz /src/plasmatube_26.08.1.orig.tar.xz .
dpkg-source -x $BASE.dsc t >/dev/null
cd t
test "$(dpkg-parsechangelog -S Distribution)" != UNRELEASED
cp /recipe/0006-*.patch debian/patches/
basename /recipe/0006-*.patch >> debian/patches/series
python3 - <<'PY'
import email.utils
from pathlib import Path
entry = Path('/recipe/changelog.txt').read_text()
assert entry.startswith('plasmatube (26.08.1-1+stereo3d5) unstable;'), entry[:60]
p = Path('debian/changelog')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + email.utils.formatdate(localtime=True) + '\n\n' + p.read_text())
c = Path('debian/control'); s = c.read_text()
old = '               libmpvqt-dev (>= 1.2.0-3+stereo3d2~),\n'
assert s.count(old) == 1
s = s.replace(old, old + '               libstereo-policy-dev (>= 1.13.0),\n')
old = 'Depends: libmpvqt3 (>= 1.2.0-3+stereo3d2~),\n'
assert s.count(old) == 1
c.write_text(s.replace(old, old + '         libstereo-policy1 (>= 1.13.0),\n'))
PY
cd ..
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../plain/* .
dpkg-source -x plasmatube_$NEWV.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source "$NEWV+lc1" --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
echo "== installing this round's builds first"
apt-get -y --no-install-recommends install /extra/libstereo-policy1_*.deb /extra/libstereo-policy-dev_*.deb > /work/extra-install.log 2>&1 || { tail -20 /work/extra-install.log; exit 1; }
dpkg-query -W libstereo-policy1 libstereo-policy-dev
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
ls /extra/libstereo-policy1_*.deb > /work/siblings.txt
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j${JOBS:-8}
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
