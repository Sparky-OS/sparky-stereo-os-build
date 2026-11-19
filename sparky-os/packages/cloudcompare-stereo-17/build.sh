#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 17 milestone 5: cloudcompare 2.13.2+git20240821+ds-7+stereo3d1+lc1, built from Debian's own source package
# with the three patches of this folder (patches/: the stereo window gets its stereo format; one 3D mode, Enable 3D, with no dialog
# and no output modes of its own; the two eyes' separation is the person's depth limits) , this folder's debian additions
# (overlay.py) and Lean Code (lean.debian_prepare, the toolkit of this tree).
#   build.sh DEBIAN.dsc WORK
# Run as an ordinary user in a disposable container that has the build dependencies of cloudcompare, libstereo-declare-dev,
# libqt5x11extras5-dev, bubblewrap, python3, dpkg-dev and devscripts, with this tree mounted. WORK must be empty. The link and
# start gate and lean.release check-debs are the next steps (README.md).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
DSC=$(readlink -f "$1") WORK=$2
REPRO=$TREE/repo/reproducible.py
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '2.13.2+git20240821+ds-7' ] || { echo "cloudcompare: this recipe is for Debian's 2.13.2+git20240821+ds-7" >&2; exit 2; }
D=$(dirname "$DSC")
cp "$D"/cloudcompare_2.13.2+git20240821+ds-7.debian.tar.xz "$D"/cloudcompare_2.13.2+git20240821+ds.orig.tar.gz "$DSC" "$WORK/"
cd "$WORK"
dpkg-source -x "$(basename "$DSC")" >/dev/null
cd cloudcompare-2.13.2+git20240821+ds
n=0
for p in "$HERE"/patches/0*.patch; do
	n=$((n + 1))
	name=stereo-$n-$(basename "$p" | sed 's/^0*[0-9]*-//')
	{
		echo "Description: $(sed -n 's/^Subject: \[PATCH [0-9/]*\] //p' "$p" | head -1)"
		echo "Author: Daniel Campos Ramos <Capitain_Jack@yahoo.com>"
		echo "Forwarded: not-needed"
		echo "Origin: vendor, Sparky Stereo OS (ORDER 17)"
		echo
		sed '1,/^---$/d' "$p"
	} > "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
python3 "$HERE/overlay.py"
python3 - "$HERE/changelog/cloudcompare.items" <<'PY' > "$WORK/items.txt"
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
VERSION=2.13.2+git20240821+ds-7+stereo3d2
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$(head -1 "$WORK/items.txt")"
while IFS= read -r item; do [ "$item" = "$(head -1 "$WORK/items.txt")" ] || dch --date "$DATE" -a "$item"; done < "$WORK/items.txt"
cat >> debian/copyright <<'EOC'

Files: debian/patches/stereo-* libs/qCC_glWindow/include/ccGLWindowDepthNotice.h
Copyright: 2026 Daniel Campos Ramos
License: GPL-2.0+
Comment: Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Pawel "pavroo" Pijanowski).
 CloudCompare is by Daniel Girardeau-Montaut and its contributors (EDF R&D, Telecom ParisTech); the quad-buffered stereo window
 and its renderer are theirs.
EOC
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
dpkg-buildpackage -us -uc -sa -j4
