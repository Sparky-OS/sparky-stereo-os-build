#!/bin/bash
# Sparky Stereo OS, ORDER 50 step 3: kicad 10.0.6+dfsg-1+stereo3d1+lc1, Debian testing's own source plus the five patches of
# patches/ (the 3D viewer's stereo pair, fitted to the person's depth limits) and the ten-language sentences of
# ../../translations/kicad-3d-viewer-stereo.po.patch.  The source and the architecture-dependent package are built
# (--build=source,any): kicad-demos, kicad-libraries and the kicad-doc-* packages are Debian's, unchanged.
#   build.sh DEBIAN.dsc WORK   (disposable container with the build dependencies, libstereo-declare-dev (>= 1.11.0),
#                               bubblewrap, clang, python3, devscripts; TREE mounted)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '10.0.6+dfsg-1' ] || { echo "kicad: this recipe is for Debian's 10.0.6+dfsg-1" >&2; exit 2; }
D=$(dirname "$DSC")
cp "$D"/kicad_10.0.6+dfsg-1.debian.tar.xz "$D"/kicad_10.0.6+dfsg.orig.tar.xz "$D"/kicad_10.0.6+dfsg.orig-doc.tar.xz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd kicad-10.0.6+dfsg
for p in "$HERE"/patches/*.patch "$TREE/translations/kicad-3d-viewer-stereo.po.patch"; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
python3 - <<'PY'
from pathlib import Path
c = Path('debian/control').read_text()
old = ' libssl-dev,\n'
assert c.count(old) == 1, 'Debian control changed'
Path('debian/control').write_text(c.replace(old, old + ' libstereo-declare-dev (>= 1.11.0),\n', 1))
# KiCad's QA test programs (qa/, KICAD_BUILD_QA_TESTS, default ON) are built by Debian's rules even under nocheck, are never
# run here and install nothing (qa/ has no install() rule); without them the build tree is far smaller.
r = Path('debian/rules').read_text()
old = '\t-DKICAD_BUILD_I18N=ON \\\n'
assert r.count(old) == 1, 'Debian rules changed'
Path('debian/rules').write_text(r.replace(old, old + '\t-DKICAD_BUILD_QA_TESTS=OFF \\\n', 1))
PY
VERSION=10.0.6+dfsg-1+stereo3d1
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
n=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	if [ $n = 0 ]; then dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
	n=$((n + 1))
done < "$HERE/changelog/kicad.items"
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
# The debug information is kept, compressed in the objects and the linked files (most of the build tree is debug
# information); dh_strip moves it into kicad-dbgsym compressed as before, and the installed files are the same files.
export DEB_CFLAGS_MAINT_APPEND='-gz=zstd' DEB_CXXFLAGS_MAINT_APPEND='-gz=zstd'
export DEB_LDFLAGS_MAINT_APPEND='-Wl,--compress-debug-sections=zstd'
dpkg-buildpackage -us -uc -sa -j4 --build=source,any
