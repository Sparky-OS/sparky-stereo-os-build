#!/bin/bash
# Sparky Stereo OS, ORDER 50 step 2: pymol 3.1.0+dfsg-1+stereo3d1+lc1, Debian unstable's own source plus patches/stereo-1.
#   build.sh DEBIAN.dsc WORK   (disposable container with the build dependencies, bubblewrap, python3, devscripts; TREE mounted)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '3.1.0+dfsg-1' ] || { echo "pymol: this recipe is for Debian's 3.1.0+dfsg-1" >&2; exit 2; }
D=$(dirname "$DSC")
cp "$D"/pymol_3.1.0+dfsg-1.debian.tar.xz "$D"/pymol_3.1.0+dfsg.orig.tar.xz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd pymol-3.1.0+dfsg
for p in "$HERE"/patches/stereo-*.patch; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
VERSION=3.1.0+dfsg-1+stereo3d1
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
n=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	if [ $n = 0 ]; then dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
	n=$((n + 1))
done < "$HERE/changelog/pymol.items"
cat >> debian/copyright <<'EOC'

Files: debian/patches/stereo-* modules/pymol/edition3d.py
Copyright: 2026 Daniel Campos Ramos
License: BSD-like
Comment: Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Pawel "pavroo" Pijanowski).
 PyMOL is by Warren L. DeLano and Schrodinger, LLC and its contributors; its quad buffer renderer is theirs.
EOC
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
dpkg-buildpackage -us -uc -sa -j4
