#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS, ORDER 17: f3d 3.5.0+dfsg-3+stereo3d1+lc1, libf3d3 and libf3d-dev, built from Debian's own source package with
# the seven patches of branch order17-stereo of Sparky-OS/f3d (patches/), this folder's debian additions (overlay.py,
# debian-add/), and Lean Code (lean.debian_prepare, the toolkit of this tree).
#   build.sh DEBIAN.dsc WORK
# Run as root in a disposable container that has the build dependencies of f3d, patchelf, python3, dpkg-dev and devscripts,
# with this tree mounted. WORK must be empty; the source and the binaries stay there. The link and start gate and
# lean.release check-debs are the next steps (README.md).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
DSC=$(readlink -f "$1") WORK=$2
REPRO=$TREE/repo/reproducible.py
# the date of the source is its recipe's (ORDER 421b)
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPRO" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
mkdir -p "$WORK"
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '3.5.0+dfsg-3' ] || { echo "f3d: this recipe is for Debian's 3.5.0+dfsg-3" >&2; exit 2; }
cp "$(dirname "$DSC")"/f3d_3.5.0+dfsg-3.debian.tar.xz "$(dirname "$DSC")"/f3d_3.5.0+dfsg.orig.tar.xz "$DSC" "$WORK/"
cd "$WORK"
dpkg-source -x "$(basename "$DSC")" >/dev/null
cd f3d-3.5.0+dfsg
for p in "$HERE"/patches/0*.patch; do
	n=stereo-$(basename "$p" | sed 's/^0*\([0-9]*\)-/\1-/')
	{
		echo "Description: $(sed -n 's/^Subject: \[PATCH [0-9/]*\] //p' "$p" | head -1)"
		echo "Author: Daniel Campos Ramos <Capitain_Jack@yahoo.com>"
		echo "Forwarded: not-needed"
		echo "Origin: vendor, https://github.com/Sparky-OS/f3d (branch order17-stereo)"
		echo
		sed '1,/^---$/d' "$p"
	} > "debian/patches/$n"
	grep -qx "$n" debian/patches/series || echo "$n" >> debian/patches/series
done
python3 "$HERE/overlay.py" "$HERE/debian-add"
python3 - "$HERE/changelog/f3d.items" <<'PY' > "$WORK/items.txt"
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
VERSION=3.5.0+dfsg-3+stereo3d1
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$(head -1 "$WORK/items.txt")"
while IFS= read -r item; do [ "$item" = "$(head -1 "$WORK/items.txt")" ] || dch --date "$DATE" -a "$item"; done < "$WORK/items.txt"
# the copyright file keeps Debian's paragraphs and gains our credit for the files we add
cat >> debian/copyright <<'EOC'

Files: debian/f3d-thumbnail-pair.cxx debian/50_sparky_stereo.json debian/patches/stereo-*
Copyright: 2026 Daniel Campos Ramos
License: BSD-3-Clause
Comment: Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Pawel "pavroo" Pijanowski).
EOC
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
dpkg-buildpackage -us -uc -sa -j4
