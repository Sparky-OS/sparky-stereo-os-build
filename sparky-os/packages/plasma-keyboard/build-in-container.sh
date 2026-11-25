#!/bin/bash
# Sparky Stereo OS: plasma-keyboard 6.7.4-2+stereo3d2, Debian's 6.7.4-2 with Plasma Keyboard as the on-screen keyboard of
# Fcitx 5 (row 71): +stereo3d1's patch 0001, then 0002 (a second touch on a focused field, the field kept in view, the told
# sentence readable), built with Lean Code.
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
for p in /patches/0001-*.patch /patches/0002-*.patch /translations/plasma-keyboard-fcitx.po.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
first = Path('/tools/changelog-stereo3d1.txt').read_text()
second = Path('/tools/changelog-stereo3d2.txt').read_text()
assert first.startswith('plasma-keyboard (6.7.4-2+stereo3d1) unstable;'), first[:60]
assert second.startswith('plasma-keyboard (6.7.4-2+stereo3d2) unstable;'), second[:60]
assert p.read_text().startswith('plasma-keyboard (6.7.4-2) unstable;'), p.read_text()[:60]
by = '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
# +stereo3d1 keeps the date its source was made with; +stereo3d2 is dated by this recipe
p.write_text(second.rstrip('\n') + by + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + first.rstrip('\n') + by + 'Wed, 25 Nov 2026 13:16:05 +0000\n\n' + p.read_text())
# the second touch and the field kept in view need the edition's KWin that says the one and does the other
c = Path('debian/control')
text = c.read_text()
old = 'Depends: qt6-virtualkeyboard-plugin,\n         ${misc:Depends},'
assert text.count(old) == 1, 'plasma-keyboard Depends'
c.write_text(text.replace(old, 'Depends: kwin-wayland (>= 4:6.7.4-2+stereo3d67~),\n         qt6-virtualkeyboard-plugin,\n         ${misc:Depends},'))
CHANGELOG
head -14 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/plasma-keyboard_6.7.4-2+stereo3d2.dsc ../s1/plasma-keyboard_6.7.4-2+stereo3d2.debian.tar.xz ../s1/plasma-keyboard_6.7.4.orig.tar.xz ../s1/plasma-keyboard_6.7.4.orig.tar.xz.asc .
dpkg-source -x plasma-keyboard_6.7.4-2+stereo3d2.dsc /work/lc/source >/dev/null
cd /work/lc/source
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 6.7.4-2+stereo3d2+lc1 --toolkit /toolkit
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap dbus >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' qt6-base-dev qt6-declarative-dev qt6-virtualkeyboard-dev liblayershellqtinterface-dev plasma-wayland-protocols extra-cmake-modules >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
sib=()
if [ -n "${SIBLINGS:-}" ]; then
	find /siblings -maxdepth 1 -name "*.deb" ! -name "*-dbgsym_*" ! -name "*-lc-hr_*" | sort > /work/siblings.txt
	sib=(SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt)
fi
# the bridge's test talks to stand-ins of KWin and Fcitx 5 on a session bus of its own
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" "${sib[@]}" dbus-run-session -- dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
