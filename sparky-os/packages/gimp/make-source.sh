#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the first +lc1 source of GIMP, 3.2.8-1+stereo3d1 (queue row 137 with row 148, the stereo GIMP's
# milestone 1): Debian's 3.2.8-1 source package (checked against source.sha256) unpacked, this folder's patches after
# Debian's series, the build and run-time dependencies of the stereo canvas in debian/control, the copyright of its new
# files, the changelog entry, then the Lean Code source (lean.debian_prepare) packed next to Debian's orig tarball.
# Nothing is built here: release/build-from-lc-dsc.sh builds the .dsc, with the staged gtk+3.0 +stereo3d1 packages as
# its siblings (build.sh does both).
#   make-source.sh DEBIAN_SOURCE OUT IMAGE
#   DEBIAN_SOURCE  a folder with gimp_3.2.8-1.dsc, its Debian tarball and gimp_3.2.8.orig.tar.xz
#   OUT            an empty folder: receives the new .dsc, its Debian tarball and the orig tarball
#   IMAGE          an image with dpkg-dev and python3 (the build image)
# The date of the source is this folder's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^#   make-source/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
SRC=$(realpath "$1") OUT=$(mkdir -p "$2" && cd "$2" && pwd) IMG=$3
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")}
(cd "$SRC" && sha256sum --check --quiet "$HERE/source.sha256")
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-gimp}-source-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$SRC":/src:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cd "$W"
	cp /src/gimp_3.2.8-1.dsc /src/gimp_3.2.8-1.debian.tar.xz /src/gimp_3.2.8.orig.tar.xz .
	dpkg-source -x gimp_3.2.8-1.dsc tree >/dev/null
	[ -z "$(tail -c1 tree/debian/patches/series)" ] || echo >> tree/debian/patches/series
	for p in stereo3d-canvas-per-eye.patch stereo3d-canvas-per-eye-po.patch; do
		cp "/recipe/patches/$p" tree/debian/patches/
		echo "$p" >> tree/debian/patches/series
	done
	(cd tree && QUILT_PATCHES=debian/patches dpkg-source --before-build . >/dev/null)
	python3 - tree/debian/control <<"CONTROL"
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)
# the stereo GtkGLArea of the edition'"'"'s GTK 3 (the canvas per eye) and OpenGL through epoxy; Debian'"'"'s libmypaint
# (deb-multimedia'"'"'s epoch-1 package would win the build otherwise and link another soname than Debian'"'"'s GIMP)
sub("               libgtk-3-dev,\n", "               libgtk-3-dev (>= 3.24.52-3+stereo3d1~),\n               libepoxy-dev,\n")
sub("               libmypaint-dev,\n", "               libmypaint-dev (<< 1:0),\n")
# View > Display Settings runs kcmshell6 (kde-cli-tools) with the display page (kscreen): a dependency a designed
# feature needs is a Depends
sub("         xdg-utils,\nRecommends: ghostscript,", "         xdg-utils,\n         kde-cli-tools,\n         kscreen,\nRecommends: ghostscript,")
p.write_text(s)
CONTROL
	python3 - tree/debian/copyright <<"COPYRIGHT"
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
anchor = "\nFiles: plug-ins/python/python-console/*\n"
assert s.count(anchor) == 1
stanza = """
Files: app/display/gimpdisplayshell-stereo.c app/display/gimpdisplayshell-stereo.h
Copyright: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
License: GPL-3+
"""
p.write_text(s.replace(anchor, stanza + anchor))
COPYRIGHT
	grep -q "^License: GPL-3+$" tree/debian/copyright
	python3 - tree/debian/changelog /recipe/changelog-stereo3d1.txt <<"CHANGELOG"
import os, sys
from pathlib import Path
sys.path.insert(0, "/toolkit/repo")
import reproducible
p = Path(sys.argv[1])
entry = Path(sys.argv[2]).read_text()
assert entry.startswith("gimp (3.2.8-1+stereo3d1) unstable;"), entry[:50]
assert p.read_text().startswith("gimp (3.2.8-1) ")
p.write_text(entry.rstrip("\n") + "\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  "
             + reproducible.rfc2822(os.environ["SOURCE_DATE_EPOCH"]) + "\n\n" + p.read_text())
CHANGELOG
	# g-ir-scanner and gi-docgen read the doc comments and annotations of libgimp'"'"'s sources and headers (the typelib and
	# libgimp-3.0-doc); the Goat Exercises show their own source in their window
	PYTHONPATH=/toolkit python3 -m lean.debian_prepare "$W/tree" 3.2.8-1+stereo3d1+lc1 --toolkit /toolkit \
		--preserve-source "libgimp*/*" "g-ir-scanner and gi-docgen read the doc comments and annotations of the libgimp sources and headers" \
		--preserve-source "extensions/*" "the Goat Exercises show their own source code to the person"
	python3 /toolkit/repo/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" tree
	dpkg-source -b tree >/dev/null
	cp gimp_3.2.8-1+stereo3d1+lc1.dsc gimp_3.2.8-1+stereo3d1+lc1.debian.tar.xz gimp_3.2.8.orig.tar.xz /out/
'
ls -la "$OUT"
