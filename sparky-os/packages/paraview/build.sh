#!/bin/bash
# Sparky Stereo OS, ORDER 50 step 5: paraview 6.1.1+dfsg1-3+stereo3d2+lc1, Debian testing's own source plus patches/ (one
# stereo output, the declared pair: Enable 3D, the View menu's two entries, ParaView's own output formats not offered) and
# ../../translations/paraview-stereo.po.patch (the sentences in the gettext domain paraview-stereo). The source and the
# architecture-dependent packages are built (--build=source,any): paraview-doc is Debian's, unchanged.
#   build.sh DEBIAN.dsc WORK   (disposable container with paraview's build dependencies, gettext, bubblewrap, clang,
#                               nodejs, node-acorn, python3-yaml, devscripts; TREE mounted)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '6.1.1+dfsg1-3' ] || { echo "paraview: this recipe is for Debian's 6.1.1+dfsg1-3" >&2; exit 2; }
echo "4a90391559148d3dee4f024b6dd961947dce82f863be569f2f4cb8d3312b86ad  $DSC" | sha256sum -c --quiet
D=$(dirname "$DSC")
cp "$D"/paraview_6.1.1+dfsg1-3.debian.tar.xz "$D"/paraview_6.1.1+dfsg1.orig.tar.gz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd paraview-6.1.1+dfsg1
for p in "$HERE"/patches/*.patch "$TREE/translations/paraview-stereo.po.patch"; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
python3 - <<'PY'
from pathlib import Path
c = Path('debian/control').read_text()
old = '               qt6-tools-dev,\n'
assert c.count(old) == 1, 'Debian control changed'
# msgfmt makes the catalogues of the 3D options' sentences (Clients/ParaView/stereo-po)
c = c.replace(old, '               gettext,\n' + old, 1)
old = 'Package: paraview\nArchitecture: any\nDepends: tclsh,\n'
assert c.count(old) == 1, 'Debian control changed'
# the View menu's "3D display settings..." runs kcmshell6 (libkf6kcmutils-bin) with KScreen's page (kcm_kscreen, in kscreen);
# kde-cli-tools as the main session's ruling names it (kscreen depends on it too)
c = c.replace(old, old + '         kde-cli-tools,\n         kscreen,\n         libkf6kcmutils-bin,\n', 1)
Path('debian/control').write_text(c)
i = Path('debian/paraview.install').read_text()
assert i.endswith('\n') and 'usr/share/locale' not in i, 'Debian paraview.install changed'
Path('debian/paraview.install').write_text(i + 'usr/share/locale/*/LC_MESSAGES/paraview-stereo.mo\n')
PY
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
# one changelog entry per edition version: +stereo3d1 (paraview.items), +stereo3d2 (paraview-stereo3d2.items)
for entry in 1:paraview.items 2:paraview-stereo3d2.items; do
	VERSION=6.1.1+dfsg1-3+stereo3d${entry%%:*}
	n=0
	while IFS= read -r item; do
		[ -n "$item" ] || continue
		if [ $n = 0 ]; then dch --date "$DATE" -v "$VERSION" -D unstable --force-distribution "$item"; else dch --date "$DATE" -a "$item"; fi
		n=$((n + 1))
	done < "$HERE/changelog/${entry#*:}"
done
export PYTHONPATH="$TREE${PYTHONPATH:+:$PYTHONPATH}"
python3 -m lean.debian_prepare "$PWD" "$VERSION+lc1" --toolkit "$TREE"
python3 "$TREE/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$PWD"
export DEB_BUILD_OPTIONS=${DEB_BUILD_OPTIONS:-parallel=4 nocheck}
# The debug information is kept, compressed in the objects and the linked files, as in the vtk9 and KiCad recipes; the
# -dbgsym packages carry all of it.
export DEB_CFLAGS_MAINT_APPEND='-gz=zstd' DEB_CXXFLAGS_MAINT_APPEND='-gz=zstd'
export DEB_LDFLAGS_MAINT_APPEND='-Wl,--compress-debug-sections=zstd'
dpkg-buildpackage -us -uc -sa -j4 --build=source,any
