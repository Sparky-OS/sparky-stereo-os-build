#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the +lc1 source of Krita 1:6.0.4.1+dfsg-1+stereo3d1 (queue row 148, Krita's milestone 1): Debian's
# 1:5.3.4.1+dfsg-1 source package (checked against source.sha256), whose tarball is upstream's krita-6.0.4.1 tree, built
# as Krita's Qt 6 flavour (Krita 6.0.4.1; on Qt 5 the canvas cannot pass 8 bits per channel and has no stereo surface):
# its orig tarball carried under that version's name (the same bytes), Debian's packaging moved to Qt 6 and KDE
# Frameworks 6 (asserted line by line, so a change of Debian's shows), this folder's patches and the catalogue patch
# after it, the copyright of the new files, the changelog entry, then the Lean Code source (lean.debian_prepare) packed
# next to the orig tarball. Nothing is built here: release/build-from-lc-dsc.sh builds the .dsc (build.sh does both).
#   make-source.sh DEBIAN_SOURCE OUT IMAGE
#   DEBIAN_SOURCE  a folder with krita_5.3.4.1+dfsg-1.dsc, its Debian tarball and krita_5.3.4.1+dfsg.orig.tar.xz
#   OUT            an empty folder: receives the new .dsc, its Debian tarball and the orig tarball
#   IMAGE          an image with dpkg-dev, quilt and python3 (the build image)
# The date of the source is this folder's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^#   make-source/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
SRC=$(realpath "$1") OUT=$(mkdir -p "$2" && cd "$2" && pwd) IMG=$3
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")}
(cd "$SRC" && sha256sum --check --quiet "$HERE/source.sha256")
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-krita}-source-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$SRC":/src:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cd "$W"
	cp /src/krita_5.3.4.1+dfsg-1.dsc /src/krita_5.3.4.1+dfsg-1.debian.tar.xz /src/krita_5.3.4.1+dfsg.orig.tar.xz .
	dpkg-source -x krita_5.3.4.1+dfsg-1.dsc tree >/dev/null
	# the Qt 6 flavour of the same tree is Krita 6.0.4.1: the same tarball under that version
	cp krita_5.3.4.1+dfsg.orig.tar.xz krita_6.0.4.1+dfsg.orig.tar.xz
	mkdir -p tree/debian/patches
	[ ! -e tree/debian/patches/series ] || { echo "Debian has a patch series now: put ours after it" >&2; exit 1; }
	while read -r p; do
		[ -n "$p" ] || continue
		cp "/recipe/patches/$p" tree/debian/patches/
		echo "$p" >> tree/debian/patches/series
	done < /recipe/patches/series
	cp /toolkit/translations/krita-order148b-canvas-per-eye.po.patch tree/debian/patches/
	echo krita-order148b-canvas-per-eye.po.patch >> tree/debian/patches/series
	(cd tree && QUILT_PATCHES=debian/patches dpkg-source --before-build . >/dev/null)
	python3 - tree/debian <<"DEBIAN"
import sys
from pathlib import Path
debian = Path(sys.argv[1])
def edit(name, pairs):
    p = debian / name
    s = p.read_text()
    for old, new in pairs:
        assert s.count(old) == 1, (name, old)
        s = s.replace(old, new)
    p.write_text(s)
edit("control", [
    ("Maintainer: Debian Qt/KDE Maintainers <debian-qt-kde@lists.debian.org>\n",
     "Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-Maintainer: Debian Qt/KDE Maintainers <debian-qt-kde@lists.debian.org>\n"),
    ("extra-cmake-modules (>= 5.91~),", "extra-cmake-modules (>= 6.0~),"),
    # KDE Frameworks 6 (KSeExpr has no Qt 6 build in Debian: its fill layer is not built, as in the earlier +stereo3d builds)
    ("""               libkf5completion-dev (>= 5.44.0),
               libkf5config-dev (>= 5.44.0),
               libkf5coreaddons-dev (>= 5.44.0),
               libkf5crash-dev (>= 5.44.0),
               libkf5guiaddons-dev (>= 5.44.0),
               libkf5i18n-dev (>= 5.44.0),
               libkf5itemviews-dev (>= 5.44.0),
               libkf5widgetsaddons-dev (>= 5.44.0),
               libkseexpr-dev (>= 4.0.0.0~),
""", """               libkf6colorscheme-dev,
               libkf6completion-dev,
               libkf6config-dev,
               libkf6coreaddons-dev,
               libkf6crash-dev,
               libkf6guiaddons-dev,
               libkf6i18n-dev,
               libkf6itemviews-dev,
               libkf6widgetsaddons-dev,
"""),
    ("""               libpoppler-qt5-dev,
               libquazip1-qt5-dev (>= 0.6~),
               libqt5opengl5-dev,
               libqt5svg5-dev (>= 5.15.0~),
               libqt5x11extras5-dev (>= 5.15.0~),
""", """               libpoppler-qt6-dev,
               libquazip1-qt6-dev (>= 0.6~),
"""),
    # the stereo layer: a document file\x27s stereo mark and the person\x27s choice for it, Enable 3D, the 3D Input Format
    ("               libsdl2-dev,\n", "               libsdl2-dev,\n               libstereo-layer-dev (>= 1.22.0~),\n"),
    # the canvas layer of the 3D canvas is a Wayland subsurface below the window
    ("               libunibreak-dev (>= 5.0~),\n", "               libunibreak-dev (>= 5.0~),\n               libwayland-dev,\n"),
    ("               pyqt5-dev,\n", "               pyqt6-dev,\n"),
    ("               python3-pyqt5,\n", "               python3-pyqt6,\n"),
    ("""               qml-module-qtqml,
               qml-module-qtqml-models2,
               qml-module-qtquick-controls2,
               qml-module-qtquick-layouts,
               qml-module-qtquick-shapes,
               qml-module-qtquick-window2,
               qml-module-qtquick2,
               qtbase5-dev (>= 5.15.0~),
               qtbase5-private-dev (>= 5.15.0~),
               qtdeclarative5-dev (>= 5.15.0~),
               qtquickcontrols2-5-dev (>= 5.15.0~),
""", """               qml6-module-qtqml,
               qml6-module-qtqml-models,
               qml6-module-qtquick,
               qml6-module-qtquick-controls,
               qml6-module-qtquick-layouts,
               qml6-module-qtquick-shapes,
               qml6-module-qtquick-window,
               qt6-5compat-dev,
               qt6-base-dev,
               qt6-base-private-dev,
               qt6-declarative-dev,
               qt6-svg-dev,
               qt6-wayland-dev,
               qt6-wayland-private-dev,
"""),
    ("               zlib1g-dev\n", "               wayland-protocols,\n               zlib1g-dev\n"),
    # the window keeps the canvas\x27s depth with its alpha only with the edition\x27s Qt (6.11.2+dfsg-5+stereo3d3 and
    # later, as +stereo3d7 needed); View > Display Settings runs kcmshell6 (libkf6kcmutils-bin) with the display page
    # (kscreen); the native Wayland platform needs Qt\x27s Wayland shell integration (qt6-wayland: without it Qt makes no
    # Wayland window and Krita runs on X11, flat and at 8 bits); its QML panels draw their icons from SVG, which Qt 6
    # decodes with qt6-svg-plugins (in Qt 5 the plugins came with libqt5svg5): a dependency a designed feature needs is
    # a Depends
    ("Depends: krita-data (>= ${source:Version}), libqt5sql5-sqlite,\n",
     "Depends: krita-data (>= ${source:Version}), libqt6widgets6 (>= 6.11.2+dfsg-5+stereo3d3), libqt6sql6-sqlite,\n"
     "         qml6-module-qtquick-controls, libkf6kcmutils-bin, kscreen, qt6-wayland, qt6-svg-plugins,\n"),
    ("Recommends: python3-pyqt5,\n", "Recommends: python3-pyqt6,\n"),
])
edit("rules", [
    ("\tdh $@ --with kf5\n", "\tdh $@ --with kf6\n"),
    ("dh_auto_configure -Skf5 -- ", "dh_auto_configure -Skf6 -- "),
    ("-DBUILD_WITH_QT6=OFF", "-DBUILD_WITH_QT6=ON -DALLOW_UNSTABLE=QT6"),
])
edit("krita.install", [("usr/lib/*/qt5/qml/org/krita/", "usr/lib/*/qt6/qml/org/krita/")])
# the link gate is told which stereo calls /usr/bin/krita stopped making on purpose (lean/archive.md): the stereo surface
# format is now asked by the layer of the canvas in libkritaui (KisStereoCanvasLayer), never set on the default format in
# main(), and the start-up "Stereo 3D" setting is replaced by Enable 3D of the stereo layer
(debian / "sparky-lean-retired-stereo-imports").write_text(
    "_ZN14QSurfaceFormat9setStereoEb the stereo surface format moved from the default format set in main() to the "
    "layer of the canvas below the window (KisStereoCanvasLayer in libkritaui), so the interface of the window is never "
    "doubled (row 148)\n"
    "_ZN9KisConfig14stereo3DCanvasEP9QSettingsb the start-up Stereo 3D setting of +stereo3d2 to +stereo3d7 is replaced by "
    "Enable 3D of the stereo layer, which needs no restart (row 148)\n")
c = debian / "copyright"
s = c.read_text()
first = s.index("\nFiles: *\n")
anchor = s.index("\nFiles: ", first + 1)
stanza = """
Files: libs/ui/opengl/KisStereoCanvasLayer.cpp libs/ui/opengl/KisStereoCanvasLayer.h
Copyright: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
License: GPL-2+
"""
c.write_text(s[:anchor] + stanza + s[anchor:])
assert "\nLicense: GPL-2+\n" in s
DEBIAN
	python3 - tree/debian/changelog /recipe/changelog-stereo3d1.txt <<"CHANGELOG"
import os, sys
from pathlib import Path
sys.path.insert(0, "/toolkit/repo")
import reproducible
p = Path(sys.argv[1])
entry = Path(sys.argv[2]).read_text()
assert entry.startswith("krita (1:6.0.4.1+dfsg-1+stereo3d1) unstable;"), entry[:60]
assert p.read_text().startswith("krita (1:5.3.4.1+dfsg-1) ")
p.write_text(entry.rstrip("\n") + "\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  "
             + reproducible.rfc2822(os.environ["SOURCE_DATE_EPOCH"]) + "\n\n" + p.read_text())
CHANGELOG
	PYTHONPATH=/toolkit python3 -m lean.debian_prepare "$W/tree" 1:6.0.4.1+dfsg-1+stereo3d1+lc1 --toolkit /toolkit
	python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" tree
	dpkg-source -b tree >/dev/null
	cp krita_6.0.4.1+dfsg-1+stereo3d1+lc1.dsc krita_6.0.4.1+dfsg-1+stereo3d1+lc1.debian.tar.xz krita_6.0.4.1+dfsg.orig.tar.xz /out/
'
ls -la "$OUT"
