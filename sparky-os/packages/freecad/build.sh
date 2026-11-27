#!/bin/bash
# Sparky Stereo OS, row 50 step 5: freecad 1.1.3+dfsg-3+stereo3d3+lc1, Debian testing's own source plus the patches of
# patches/ (the 3D view in stereo: two cameras fitted to the person's depth limits, a translucent pixel at the weighted
# mean of what it shows, the viewport a declared 3D area in every render type, Enable 3D and the desktop's display
# settings as its 3D options) and the ten-language sentences of ../../translations/freecad-3d-view-stereo.ts.patch.
# After the build, the stereo fit's unit test (FreeCAD's Gui_tests_run, View3DStereoFit) runs from the build tree; its
# output is WORK/freecad-view3dstereofit-test.txt, and a failure fails the recipe.  Every package of the source is built: freecad-common and freecad
# (all) depend on the exact version of freecad-python3 and libfreecad-python3.
#   build.sh DEBIAN.dsc WORK   (disposable container with the build dependencies, libstereo-declare-dev (>= 1.12.2),
#                               qt6-base-private-dev, pkgconf, bubblewrap, clang, python3, devscripts; TREE set)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${TREE:?the sparky-os folder of the build tree}
DSC=$(readlink -f "$1") WORK=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL='Capitain_Jack@yahoo.com'
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TREE/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
mkdir -p "$WORK"; [ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
[ "$(sed -n 's/^Version: //p' "$DSC")" = '1.1.3+dfsg-3' ] || { echo "freecad: this recipe is for Debian's 1.1.3+dfsg-3" >&2; exit 2; }
D=$(dirname "$DSC")
printf '%s  %s\n' f8d1383bffd7279c7282f659062ae4fe06cc94d0c6076e498949f70358c59ceb "$DSC" \
	d783843dc377717c462f5330fc20a769ebea0fc8b0898e50507ef35e50b7ddd2 "$D/freecad_1.1.3+dfsg.orig.tar.xz" \
	edbe716fbb0e4b30bc4ede3cb375ad83402e5fc849b4879772d855dd2ce25e76 "$D/freecad_1.1.3+dfsg-3.debian.tar.xz" | sha256sum -c --quiet
cp "$D"/freecad_1.1.3+dfsg-3.debian.tar.xz "$D"/freecad_1.1.3+dfsg.orig.tar.xz "$DSC" "$WORK/"
cd "$WORK"; dpkg-source -x "$(basename "$DSC")" >/dev/null; cd freecad-1.1.3+dfsg
for p in "$HERE"/patches/*.patch "$TREE/translations/freecad-3d-view-stereo.ts.patch"; do
	name=$(basename "$p"); cp "$p" "debian/patches/$name"
	grep -qx "$name" debian/patches/series || echo "$name" >> debian/patches/series
done
python3 - <<'PY'
from pathlib import Path
c = Path('debian/control').read_text()
for old, new in (
        (' libspnav-dev,\n', ' libspnav-dev,\n               libstereo-declare-dev (>= 1.12.2),\n               libtbb-dev,\n'),
        (' pybind11-dev,\n', ' pkgconf,\n               pybind11-dev,\n'),
        (' qt6-base-dev,\n', ' qt6-base-dev,\n               qt6-base-private-dev,\n'),
        # libFreeCADGui reads its window's handles through Qt's private QPlatformNativeInterface, which has no
        # compatibility between Qt versions: the library depends on the Qt it was built with
        ('Package: libfreecad-python3\nArchitecture: any\nSection: libs\nDepends: ${misc:Depends},\n         ${shlibs:Depends}\n',
         'Package: libfreecad-python3\nArchitecture: any\nSection: libs\nDepends: ${misc:Depends},\n         ${shlibs:Depends},\n         ${qt6:private-abi}\n')):
    assert c.count(old) == 1, ('Debian control changed', old)
    c = c.replace(old, new, 1)
Path('debian/control').write_text(c)
r = Path('debian/rules').read_text()
assert 'override_dh_gencontrol' not in r, 'Debian rules changed'
r += ('\n# libfreecad-python3 depends on the Qt private ABI it was built with (libqt6core6t64 provides\n'
      "# qt6-base-private-abi with Qt's upstream version)\n"
      "QT6_ABI := $(shell dpkg-query -W -f='$${Version}' qt6-base-dev | sed -e 's/[+~-].*//')\n"
      'override_dh_gencontrol:\n'
      '\tdh_gencontrol -- "-Vqt6:private-abi=qt6-base-private-abi (= $(QT6_ABI))"\n')
Path('debian/rules').write_text(r)
PY
DATE=$(date -u -d "@$SOURCE_DATE_EPOCH" -R)
# Retain the earlier stereo entries, then record the MED library transition.
for entry in 1:freecad.items 2:freecad-stereo3d2.items 3:freecad-stereo3d3.items; do
	VERSION=1.1.3+dfsg-3+stereo3d${entry%%:*}
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
# The debug information is kept, compressed in the objects and the linked files (most of the build tree is debug
# information); dh_strip moves it into the -dbgsym packages compressed as before, and the installed files are the same.
export DEB_CFLAGS_MAINT_APPEND='-gz=zstd' DEB_CXXFLAGS_MAINT_APPEND='-gz=zstd'
export DEB_LDFLAGS_MAINT_APPEND='-Wl,--compress-debug-sections=zstd'
dpkg-buildpackage -us -uc -sa -j4
# The stereo fit's unit test, from the build tree (the test binary is built with the packages; Debian's test step is
# off here, and its failures are ignored where it runs)
LD_LIBRARY_PATH="$PWD/obj-x86_64-linux-gnu/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" xvfb-run -a \
	obj-x86_64-linux-gnu/tests/Gui_tests_run --gtest_filter='View3DStereoFit.*' > "$WORK/freecad-view3dstereofit-test.txt" 2>&1 \
	|| { tail -30 "$WORK/freecad-view3dstereofit-test.txt" >&2; echo "freecad: the stereo fit's unit test failed" >&2; exit 3; }
tail -3 "$WORK/freecad-view3dstereofit-test.txt"
