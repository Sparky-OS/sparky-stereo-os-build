#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: gimp 3.2.8-1+stereo3d3+lc1 (queue row 137, the stereo GIMP's milestone 3: the deep and HDR canvas),
# the successor of 3.2.8-1+stereo3d2+lc1 made by repo/lc-successor.py --in-place --overlay: the predecessor's debian/
# stays as it is (its changelog a byte identical suffix of the new one) but for this tree's Lean Code toolkit and the
# overlay: the deep canvas's two patches after the series, debian/control (Build-Depends libgtk-3-dev
# (>= 3.24.52-3+stereo3d2~), whose GtkGLArea hands a plain area's deep picture to the compositor, and liblcms2-dev, which
# GIMP's build already has) and debian/copyright (the new files). Nothing is built here: release/build-from-lc-dsc.sh
# builds the .dsc (build.sh does both).
#   make-source-3.sh PREVIOUS OUT IMAGE
#   PREVIOUS  a folder with gimp_3.2.8-1+stereo3d2+lc1.dsc, its Debian tarball and gimp_3.2.8.orig.tar.xz
#   OUT       an empty folder: receives the new .dsc and Debian tarball and the orig tarball
#   IMAGE     an image with dpkg-dev and python3 (the build image)
# The date of the source is this folder's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^#   make-source-3/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
PREV=$(realpath "$1") OUT=$(mkdir -p "$2" && cd "$2" && pwd) IMG=$3
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")}
(cd "$PREV" && sha256sum --check --quiet --ignore-missing "$HERE/source-stereo3d2.sha256")
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-gimp}-source3-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$PREV":/prev:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cd "$W"
	cp /prev/gimp_3.2.8-1+stereo3d2+lc1.dsc /prev/gimp_3.2.8-1+stereo3d2+lc1.debian.tar.xz /prev/gimp_3.2.8.orig.tar.xz .
	dpkg-source -x --skip-patches gimp_3.2.8-1+stereo3d2+lc1.dsc prev >/dev/null
	mkdir -p overlay/patches
	for p in stereo3d-deep-canvas.patch stereo3d-deep-canvas-po.patch; do
		cp "/recipe/patches/$p" overlay/patches/
	done
	cp prev/debian/patches/series overlay/patches/series
	[ -z "$(tail -c1 overlay/patches/series)" ] || echo >> overlay/patches/series
	printf "%s\n" stereo3d-deep-canvas.patch stereo3d-deep-canvas-po.patch >> overlay/patches/series
	python3 - prev/debian/control overlay/control <<"CONTROL"
import sys
from pathlib import Path
s = Path(sys.argv[1]).read_text()
def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)
# the plain GtkGLArea that hands a deep picture to the compositor (GTK 3 +stereo3d2)
sub("libgtk-3-dev (>= 3.24.52-3+stereo3d1~)", "libgtk-3-dev (>= 3.24.52-3+stereo3d2~)")
# the canvas reads a profile'"'"'s cicp tag and builds its linear Rec. 2020 profile with Little-CMS, as GIMP does elsewhere
assert "liblcms2-dev" in s
Path(sys.argv[2]).write_text(s)
CONTROL
	python3 - prev/debian/copyright overlay/copyright <<"COPYRIGHT"
import sys
from pathlib import Path
s = Path(sys.argv[1]).read_text()
anchor = "\nFiles: plug-ins/python/python-console/*\n"
assert s.count(anchor) == 1
stanza = """
Files: app/display/gimpdisplayshell-deep.c app/display/gimpdisplayshell-deep.h
Copyright: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
License: GPL-3+
"""
Path(sys.argv[2]).write_text(s.replace(anchor, stanza + anchor))
COPYRIGHT
	grep -q "^License: GPL-3+$" overlay/copyright
	mkdir -p "$W/successor"
	PYTHONPATH=/toolkit python3 /toolkit/repo/lc-successor.py --work "$W/successor" --in-place --overlay overlay --reapply-patches --next 3.2.8-1+stereo3d3 \
		--item "Sparky Stereo OS: the deep and HDR canvas (queue row 137, the stereo GIMP'"'"'s milestone 3; stereo3d-deep-canvas). An image deeper than 8 bits, or whose profile carries ITU-T H.273 code points (an ICC cicp tag) or reaches outside sRGB'"'"'s gamut, is shown in its own depth and colour state: its canvas goes to the compositor through the GtkGLArea of the edition'"'"'s GTK 3, a stereo image'"'"'s two views and a 2D image'"'"'s one picture, rendered in floats (each eye'"'"'s cache and picture CAIRO_FORMAT_RGBA128F, the textures in float) and described: the image'"'"'s own code points, sRGB (1/13) or linear sRGB (1/8) for GIMP'"'"'s own profiles, otherwise linear Rec. 2020 (9/8), to which the display transform converts after soft-proofing and the display filters instead of to the monitor'"'"'s profile. The depth follows the precision: 8 bits, 16 bit integer, half float, and float for 32 bit integer, float and double. The compositor converts to each screen; GIMP never tone-maps for a screen. Where a depth or a description cannot reach the compositor (X11, a transfer function the compositor does not list, a half float picture on a software renderer) the canvas takes the next step down (16 bit integer, then a stereo image in 8 bit sRGB, a 2D image the 8 bit canvas) and the status bar says so; the reason is in the log." \
		--item "The strings in nine languages besides English (stereo3d-deep-canvas-po)." \
		--item "debian/control: Build-Depends libgtk-3-dev (>= 3.24.52-3+stereo3d2~)." \
		--item "debian/copyright: the new files." \
		--source-date-epoch "$SOURCE_DATE_EPOCH" gimp_3.2.8-1+stereo3d2+lc1.dsc /out
	cp gimp_3.2.8.orig.tar.xz /out/
'
ls -la "$OUT"
