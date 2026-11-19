#!/bin/bash
# Sparky Stereo OS, ORDER 50 step 2: netgen 6.2.2606+dfsg1-3+stereo3d1+lc1, Debian testing's own source plus the four patches of patches/.
#   build.sh DEBIAN.dsc WORK   (disposable container with the build dependencies, bubblewrap, python3, devscripts; TREE mounted)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '6.2.2606+dfsg1-3' ] || { echo "netgen: this recipe is for Debian's 6.2.2606+dfsg1-3" >&2; exit 2; }
D=$(dirname "$DSC")
cp "$D"/netgen_6.2.2606+dfsg1-3.debian.tar.xz "$D"/netgen_6.2.2606+dfsg1.orig.tar.xz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd netgen-6.2.2606+dfsg1
for p in "$HERE"/patches/*.patch; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
python3 - <<'PY'
from pathlib import Path
c = Path('debian/control').read_text()
old = ' libnglib-dev (>= ${binary:Version}),\n'
assert c.count(old) == 1, 'Debian control changed'
Path('debian/control').write_text(c.replace(old, ' libnglib-6.2t64 (= ${binary:Version}),\n', 1))
PY
VERSION=6.2.2606+dfsg1-3+stereo3d1
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
n=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	if [ $n = 0 ]; then dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
	n=$((n + 1))
done < "$HERE/changelog/netgen.items"
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
dpkg-buildpackage -us -uc -sa -j4
