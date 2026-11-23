#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the Oxygen icon theme with the icon cache it lost (queue row 850b, with row 59; Daniel, 2026-10-14:
# "we need the entire oxygen suite from kde"). Debian's oxygen-icon-theme 5:6.32.0-1 installs with no icon-theme.cache in
# /usr/share/icons/oxygen: gtk-update-icon-cache rejects the cache it generates ("The generated cache was invalid") while
# three entries whose names contain a space are present (simbolicActions/22x22 and 24x24/actions/go-first copy.svg and a
# symlink at 48x48). KDE removed them after the 6.32.0 tag: upstream commit 5bfe432258fff393d65442ae275f3126df90de8c,
# Nuno Pinheiro, 2026-11-16, "Remove duplicate go-first icons that invalidate GTK cache" (KDE bug 528955; Debian bug
# 1154120), carried unchanged. Debian's packaging stays as Debian has it. Lean Code at +lc1.
# Retired when Debian's own fix reaches testing (README.md).
# Run inside a clean distribution build container with the source dependencies installed.
# SOURCE_DSC names Debian's unmodified kf6-oxygen-icons_6.32.0-1.dsc and its adjacent archives.
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
: "${SOURCE_DSC:?Set SOURCE_DSC to Debian kf6-oxygen-icons_6.32.0-1.dsc}"
: "${BUILD_ROOT:?Set BUILD_ROOT to a new disposable directory}"
: "${OUT:?Set OUT to a new candidate directory}"
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS="parallel=${JOBS:-4}"
export LC_ALL=C.UTF-8
# The epoch is Debian's own (the source and its binary are 5:); it sorts above 5:6.32.0-1, the last binary a machine can
# have, and below any Debian 5:6.32.0-2 or later, which is the retirement.
VERSION=5:6.32.0-1+sparky1
V=${VERSION#*:}
printf '%s  %s\n' d69f69392ad6d7ebf53b291ee8983e70e1c0168af3995e86b7816ceaf69dd3a0 "$SOURCE_DSC" | sha256sum -c -
[ ! -e "$BUILD_ROOT/authored" ] && [ ! -e "$OUT/authored" ]
mkdir -p "$BUILD_ROOT" "$OUT/authored"
cp "$(dirname "$SOURCE_DSC")"/kf6-oxygen-icons_6.32.0.orig.tar.* "$BUILD_ROOT/"
dpkg-source -x "$SOURCE_DSC" "$BUILD_ROOT/authored"
cd "$BUILD_ROOT/authored"
# Debian 5:6.32.0-1 carries no patches: the series starts here
[ ! -e debian/patches ]
mkdir debian/patches
cp "$HERE/patches/upstream-01-5bfe4322.patch" debian/patches/
printf '%s\n' upstream-01-5bfe4322.patch > debian/patches/series
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
for f in 'simbolicActions/22x22/actions/go-first copy.svg' 'simbolicActions/24x24/actions/go-first copy.svg' \
		'simbolicActions/48x48/actions/go-first copy.svg'; do
	[ -e "$f" ] || [ -L "$f" ] || { echo "Debian's source no longer has $f: the patch is not needed" >&2; exit 1; }
done
dpkg-source --before-build .
for f in 'simbolicActions/22x22/actions/go-first copy.svg' 'simbolicActions/24x24/actions/go-first copy.svg' \
		'simbolicActions/48x48/actions/go-first copy.svg'; do
	[ ! -e "$f" ] && [ ! -L "$f" ] || { echo "the patch left $f" >&2; exit 1; }
done
# no other name with a space is left in the theme (quilt keeps its backups of the removed files in .pc)
spaced=$(find . \( -path ./debian -o -path ./.pc \) -prune -o -name '* *' -print)
[ -z "$spaced" ] || { printf 'a name with a space is left, gtk-update-icon-cache would reject the cache: %s\n' "$spaced" >&2; exit 1; }
dch --date "$SOURCE_DATE_RFC2822" --newversion "$VERSION" --distribution mashtabba \
	'Carried by Sparky Stereo OS (queue row 850b): upstream 5bfe4322 (Nuno Pinheiro), which removes the three "go-first copy.svg" entries that left the theme without its icon cache (KDE bug 528955, Debian bug 1154120). Retired when Debian'"'"'s fix reaches testing.'
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
dpkg-source -b .
cp "$BUILD_ROOT"/*.dsc "$BUILD_ROOT"/*.debian.tar.* "$BUILD_ROOT"/*.orig.tar.* "$OUT/authored/"
dpkg-source -x "$BUILD_ROOT/kf6-oxygen-icons_${V}.dsc" "$BUILD_ROOT/lean-source"
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
