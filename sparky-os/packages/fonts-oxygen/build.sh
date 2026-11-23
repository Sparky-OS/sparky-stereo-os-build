#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the Oxygen fonts, part of the whole Oxygen suite (queue row 59; Daniel, 2026-10-14: "we need the
# entire oxygen suite from kde"). Debian removed oxygen-fonts from unstable on 2025-02-28 ("ROM; Abandoned upstream",
# #1099100); bookworm is the last release that has it. KDE keeps the tree as unmaintained/oxygen-fonts, whose master has
# one font change after the last release, 5.4.3: Miro Hrončok's "Fix ď and ť in regular and bold fonts" (2e3c79fd, 2018),
# carried as a patch. Debian's 01_add-metainfo.patch is already upstream's 4966db2c (Matthias Klumpp).
# CMake 4 refuses the tree's cmake_minimum_required(VERSION 2.8.12) ("Compatibility with CMake < 3.5 has been removed"):
# our cmake-minimum-3.16.patch raises it the way Nicolas Fella raised oxygen-gtk's (a8798db8, KDE).
# The fonts are built from their .sfd sources with FontForge, as Debian builds them. Lean Code at +lc1.
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names Debian's unmodified oxygen-fonts_5.4.3-4.dsc and its adjacent archives.
# Last update 2026/11/23
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO="$HERE/../../repo/reproducible.py"
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
: "${SPARKY_LC_ARCHIVE_CONFIG:?Set an explicit public signed archive configuration}"
: "${SPARKY_LC_SCRATCH:?Set private archive qualification scratch}"
: "${LEAN_TOOLKIT:?Set the accepted archive-backed Lean Code toolkit}"
[ -f "$LEAN_TOOLKIT/lean/archive.py" ] || { echo 'Archive-backed Lean Code toolkit required' >&2; exit 1; }
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian oxygen-fonts_5.4.3-4.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS="parallel=${JOBS:-4}"
export LC_ALL=C.UTF-8
VERSION=4:5.4.3-4+sparky1
V=${VERSION#*:}
printf '%s  %s\n' dda16a84cd4bba071bad7a9c5eb62313faab255961f6f8eb423699a6433b1a43 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/authored" ]
mkdir -p "$BUILD_ROOT" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/oxygen-fonts_5.4.3.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
for patch in upstream-fix-dcaron-tcaron.patch cmake-minimum-3.16.patch; do
	cp "$HERE/patches/$patch" debian/patches/
	printf '%s\n' "$patch" >> debian/patches/series
done
python3 - <<'PY'
from pathlib import Path
path = Path('debian/control')
text = path.read_text()
old = next(line for line in text.splitlines() if line.startswith('Maintainer: '))
text = text.replace(old, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-' + old, 1)
home = next(line for line in text.splitlines() if line.startswith('Homepage: '))
text = text.replace(home, 'Homepage: https://sparkylinux.org\nBugs: https://github.com/Sparky-OS/sparky-stereo-os/issues', 1)
path.write_text(text)
PY
# our patch is credited after Debian's paragraphs; the carried commit stays its author's (provenance-files.py reads the headers)
python3 "$LEAN_TOOLKIT/repo/provenance-files.py" . 'upstream-fix-dcaron-tcaron.patch' 'cmake-minimum-3.16.patch'
dpkg-source --before-build .
grep -q 'cmake_minimum_required(VERSION 3.16)' CMakeLists.txt
dch --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'Carried by Sparky Stereo OS after Debian removed it (queue row 59): upstream 2e3c79fd (Miro Hrončok, fix ď and ť), and CMake 3.16 as the minimum, which CMake 4 needs.'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-source -b .
cp "$BUILD_ROOT"/*.dsc "$BUILD_ROOT"/*.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/oxygen-fonts_${V}.dsc" "$BUILD_ROOT/lean-source"
PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.debian_prepare "$BUILD_ROOT/lean-source" "$VERSION+lc1" --toolkit "$LEAN_TOOLKIT"
cd "$BUILD_ROOT/lean-source"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-buildpackage -us -uc -j"${JOBS:-4}"
# the stage is the source closure, in one folder: the archives, the .dsc and every file it names, the buildinfo and the changes
cp "$BUILD_ROOT"/*+lc1_*.deb "$BUILD_ROOT"/*+lc1.dsc "$BUILD_ROOT"/*+lc1.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* \
	"$BUILD_ROOT"/*+lc1_*.buildinfo "$BUILD_ROOT"/*+lc1_*.changes "$OUT/"
(cd "$OUT" && PYTHONPATH="$LEAN_TOOLKIT" python3 -m lean.release check-debs ./*.deb)
cp .sparky-lc/source.json "$OUT/native-source.json"
(cd "$OUT" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
