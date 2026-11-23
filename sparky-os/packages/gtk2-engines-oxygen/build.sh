#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: KDE's Oxygen engine for GTK 2 programs, part of the whole Oxygen suite (queue row 59; Daniel,
# 2026-10-14: "we need the entire oxygen suite from kde"). Debian removed gtk2-engines-oxygen from unstable on 2024-11-11
# ("ROM; Abandoned upstream", #1086060); bookworm is the last release that has it. KDE's plasma/oxygen-gtk master has 13
# commits after v1.4.6 and no release since; the five that change the engine or its build are carried unchanged:
# e14fbdc0 (Heiko Becker, FindPkgConfig), ef3c0cdf (Hugo Pereira Da Costa, Matt Whitlock's fix for a crash on invalid tree
# view columns, KDE bug 338012), 7a5425d8 (Hugo Pereira Da Costa, compiler warning), a8798db8 (Nicolas Fella, CMake 3.16,
# which CMake 4 needs: Debian's source stops at "Compatibility with CMake < 3.5 has been removed"), e5950db7 (Andreas
# Sturmlechner, -Wuninitialized). Left out: d5e91221 (the demo switch; Debian's dont-build-demos.patch does the same),
# b1ee5fb8 (the Mozilla program names moved to a header: no Mozilla program is a GTK 2 program any more) and the 2021
# licence-header conversions. Debian's packaging stays as Debian has it but for debhelper compat 10 (below). Lean Code at +lc1.
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names Debian's unmodified gtk2-engines-oxygen_1.4.6-1.1.dsc and its adjacent archives.
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
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian gtk2-engines-oxygen_1.4.6-1.1.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS="parallel=${JOBS:-4}"
export LC_ALL=C.UTF-8
VERSION=1.4.6-1.1+sparky1
V=${VERSION#*:}
printf '%s  %s\n' 912301099eef548582838a50c3a05fd8cec4f2dccfaa07509437ec47dbf1bfcd "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/authored" ]
mkdir -p "$BUILD_ROOT" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/gtk2-engines-oxygen_1.4.6.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
for patch in upstream-01-e14fbdc0.patch upstream-02-ef3c0cdf.patch upstream-03-7a5425d8.patch upstream-04-a8798db8.patch upstream-05-e5950db7.patch; do
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
# every carried commit stays its author's (provenance-files.py reads the headers)
python3 "$LEAN_TOOLKIT/repo/provenance-files.py" . 'upstream-*.patch'
# Lean Code's prepare step adds execute_before_dh_auto_clean and execute_before_dh_auto_configure to debian/rules, which
# dh accepts from compat 10 ("Hook target ... is only supported in compat 10 or later"); Debian's compat 9 is also
# deprecated in debhelper 14 ("Compatibility levels before 10 are deprecated"). Compat 10 changes nothing this CMake
# build uses: --parallel, which Debian's rules already pass, becomes the default.
grep -qx 9 debian/compat
printf '10\n' > debian/compat
dpkg-source --before-build .
grep -q 'cmake_minimum_required(VERSION 3.16)' CMakeLists.txt
grep -q 'DEBIAN_NO_DEMOS' CMakeLists.txt
dch --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'Carried by Sparky Stereo OS after Debian removed it (queue row 59): upstream e14fbdc0, ef3c0cdf (crash on invalid tree view columns), 7a5425d8, a8798db8 (CMake 3.16, which CMake 4 needs) and e5950db7; debhelper compat 10, which the Lean Code hooks need.'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-source -b .
cp "$BUILD_ROOT"/*.dsc "$BUILD_ROOT"/*.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/gtk2-engines-oxygen_${V}.dsc" "$BUILD_ROOT/lean-source"
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
