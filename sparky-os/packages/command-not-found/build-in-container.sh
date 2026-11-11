#!/bin/bash
# Sparky Stereo OS: command-not-found 23.04.0-3+sparky1, Debian's 23.04.0-3 with the renamed-commands table, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor build for the link gate, /tools this folder (its patches, the table and the changelog entry).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
VERSION=23.04.0-3+sparky1
cd /work
mkdir s1 && cd s1
# Debian's 23.04.0-3 source package (the .dsc pins the files)
echo 'd15130ca2dd6c11332cda2a6168b16cfb78f012f642d405c9f15dffd120184dd  /src/command-not-found_23.04.0-3.dsc' | sha256sum -c
cp /src/command-not-found_23.04.0-3.dsc /src/command-not-found_23.04.0-3.debian.tar.xz /src/command-not-found_23.04.0.orig.tar.xz .
dpkg-source -x command-not-found_23.04.0-3.dsc t >/dev/null
cd t
# our patches after Debian's series: the code, its tests and messages; the table, made from this folder's copy; the
# messages upstream left untranslated in the nine languages (sparky-os/translations)
cp /tools/patches/sparky-renamed-commands.patch debian/patches/
{
	printf 'Description: The commands Debian installs under another name\n'
	printf ' Made by make-renamed.py (Sparky Stereo OS build tree, sparky-os/packages/command-not-found).\n'
	printf 'Author: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nForwarded: no\nLast-Update: 2026-11-02\n---\n'
	diff -Nu --label /dev/null --label b/data/renamed-commands /dev/null /tools/renamed-commands || [ $? = 1 ]
} >debian/patches/sparky-renamed-commands-table.patch
cp /toolkit/translations/command-not-found-messages.po.patch debian/patches/sparky-translations.patch
printf '%s\n' sparky-renamed-commands.patch sparky-renamed-commands-table.patch sparky-translations.patch >>debian/patches/series
python3 - <<'PY'
from pathlib import Path
import os
path = Path('debian/control')
text = path.read_text()
old = 'Maintainer: Julian Andres Klode <jak@debian.org>\n'
assert text.count(old) == 1
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old)
old = 'Standards-Version: 4.6.0\n'
assert text.count(old) == 1
text = text.replace(old, old + 'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues\n')
path.write_text(text)
p = Path('debian/changelog')
entry = Path('/tools/changelog-sparky1.txt').read_text()
assert entry.startswith('command-not-found (23.04.0-3+sparky1) mashtabba;'), entry[:60]
assert p.read_text().startswith('command-not-found (23.04.0-3) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
             + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
PY
head -20 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
cmp <(dpkg-source -x command-not-found_$VERSION.dsc check >/dev/null && cat check/data/renamed-commands) /tools/renamed-commands
rm -rf check
mkdir -p /work/lc && cd /work/lc
cp ../s1/command-not-found_$VERSION.dsc ../s1/command-not-found_$VERSION.debian.tar.xz ../s1/command-not-found_23.04.0.orig.tar.xz .
dpkg-source -x command-not-found_$VERSION.dsc /work/lc/authored >/dev/null
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/authored $VERSION+lc1 --toolkit /toolkit
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/authored
(cd /work/lc/authored && dpkg-source -b . >/dev/null)
dpkg-source -x command-not-found_$VERSION+lc1.dsc /work/lc/source >/dev/null
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
dpkg-query -W -f '${Package} ${Version}\n' python3 python3-apt dh-python debhelper >/work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
