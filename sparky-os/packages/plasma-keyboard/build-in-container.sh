#!/bin/bash
# Sparky Stereo OS: plasma-keyboard 6.7.4-2+stereo3d1, Debian's 6.7.4-2 with Plasma Keyboard as the on-screen keyboard of
# Fcitx 5 (row 71), built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Runs inside the build container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor build for the link gate, /patches this folder's patches, /translations the edition's strings.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's 6.7.4-2 source package (the .dsc pins the files)
echo '527c9543d54a4c32b64bdf051f87caf8b747aa8ac6da7d83f0bb6408cb4a18cc  /src/plasma-keyboard_6.7.4-2.dsc' | sha256sum -c
cp /src/plasma-keyboard_6.7.4-2.dsc /src/plasma-keyboard_6.7.4-2.debian.tar.xz /src/plasma-keyboard_6.7.4.orig.tar.xz /src/plasma-keyboard_6.7.4.orig.tar.xz.asc .
dpkg-source -x plasma-keyboard_6.7.4-2.dsc t >/dev/null
cd t
# the code first, the edition's translations of its strings last (sparky-os/translations/README.md)
for p in /patches/0001-*.patch /translations/plasma-keyboard-fcitx.po.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('plasma-keyboard (6.7.4-2+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('plasma-keyboard (6.7.4-2) unstable;'), p.read_text()[:60]
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
CHANGELOG
head -14 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/plasma-keyboard_6.7.4-2+stereo3d1.dsc ../s1/plasma-keyboard_6.7.4-2+stereo3d1.debian.tar.xz ../s1/plasma-keyboard_6.7.4.orig.tar.xz ../s1/plasma-keyboard_6.7.4.orig.tar.xz.asc .
dpkg-source -x plasma-keyboard_6.7.4-2+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 6.7.4-2+stereo3d1+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap dbus >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' qt6-base-dev qt6-declarative-dev qt6-virtualkeyboard-dev liblayershellqtinterface-dev plasma-wayland-protocols extra-cmake-modules >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
# the bridge's test talks to stand-ins of KWin and Fcitx 5 on a session bus of its own
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dbus-run-session -- dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
