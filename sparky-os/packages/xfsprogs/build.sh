#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: Debian's xfsprogs 7.2.0-1 with upstream's fix for xfs_healer@- on a root that is not XFS (ORDER
# 346c, item 140: "xfs_healer@- (xfsprogs starts it on an ext4 /)"). xfsprogs' postinst enables xfs_healer@.service,
# whose DefaultInstance=- is /, and "xfs_healer --supported /" ended with status 255 there, a failure at every boot.
# Upstream fixed it in v7.2.1 (Debian bug #1149571, reported by Michael Biebl): d28edf8 "xfs_healer: correct xfd_ API
# usage" and fde1eee "xfs_healer: fail earlier on non-xfs filesystems", both by Darrick J. Wong, reviewed by Andrey
# Albershteyn; the second makes a file system that is not XFS a "not supported" (status 1, systemd skips the unit)
# and leaves 255 for real failures. We carry both commits unchanged as patches (patches/, DEP-3), our changelog
# entry and the maintainer fields, then Lean Code at +lc1. Drop this build when Debian ships xfsprogs 7.2.1 or later.
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names the unmodified Debian xfsprogs_7.2.0-1.dsc and its adjacent archives. With LINK_GATE_ON_HOST=1 the
# disposable build tree leaves Lean Code's link gate out (it needs bubblewrap and the archive-qualified universe), and
# `python3 -m lean.release check-link` must then run on the built archives where those are.
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
: "${LEAN_TOOLKIT:=$(cd "$HERE/../.." && pwd)}"
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian xfsprogs_7.2.0-1.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com LC_ALL=C.UTF-8
VERSION=7.2.0-1+sparky1
printf '%s  %s\n' f8b4a00f6dc130285baecdf79cf48fa4fb247f54d0ec28c285c6e952e42597ca "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/source" ]
mkdir -p "$BUILD_ROOT" "$OUT/source" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/xfsprogs_7.2.0.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
python3 - <<'PY'
import re
from pathlib import Path
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old, 1)
text = text.replace('Homepage: https://xfs.wiki.kernel.org/',
                    'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues', 1)
path.write_text(text)
PY
mkdir -p debian/patches
for p in xfs_healer-correct-xfd-api-usage.patch xfs_healer-fail-earlier-on-non-xfs-filesystems.patch; do
	cp "$HERE/patches/$p" debian/patches/
	printf '%s\n' "$p" >> debian/patches/series
done
dpkg-source --before-build .
grep -q 'if (ret == ENOTTY) {' healer/xfs_healer.c
dch --newversion "$VERSION" --distribution mashtabba \
	'Carry upstream d28edf8 and fde1eee (v7.2.1, Darrick J. Wong; Closes Debian #1149571 here): xfs_healer --supported on a file system that is not XFS ends with status 1, so systemd skips xfs_healer@- on an ext4 root.'
dpkg-source -b . >/dev/null
cd "$BUILD_ROOT"
cp xfsprogs_${VERSION}.dsc xfsprogs_${VERSION}.debian.tar.* xfsprogs_7.2.0.orig.tar.* "$OUT/authored/"
dpkg-source -x "xfsprogs_${VERSION}.dsc" lean-source >/dev/null
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare lean-source "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
(cd lean-source && dpkg-source -b . >/dev/null)
dpkg-source -x "xfsprogs_${VERSION}+lc1.dsc" build >/dev/null
if [ "${LINK_GATE_ON_HOST:-0}" = 1 ]; then
	n=$(grep -c 'python3 -m lean.debhelper --provenance' build/debian/rules)
	[ "$n" = 1 ]
	cat >"$BUILD_ROOT/builddeb-nogate.py" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
sys.path.insert(0, str(root / 'debian/sparky-lean-toolkit'))
from lean import debhelper
debhelper.link_gate = lambda built: print('link gate on the host: lean.release check-link', ' '.join(p.name for p in built))
debhelper.build(root, root / 'debian/sparky-lean-toolkit/provenance.sh')
PY
	sed -i "s|^\tPYTHONPATH=\$(CURDIR)/debian/sparky-lean-toolkit python3 -m lean.debhelper --provenance .*\$|\tpython3 $BUILD_ROOT/builddeb-nogate.py \$(CURDIR)|" build/debian/rules
fi
(cd build && dpkg-buildpackage -us -uc -b -j4)
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.release check-debs "$BUILD_ROOT"/*+lc1_*.deb
cp "$BUILD_ROOT"/*+lc1_*.deb "$OUT/"
cp "$BUILD_ROOT"/xfsprogs_${VERSION}+lc1.dsc "$BUILD_ROOT"/xfsprogs_${VERSION}+lc1.debian.tar.* "$BUILD_ROOT"/xfsprogs_7.2.0.orig.tar.* "$OUT/source/"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
