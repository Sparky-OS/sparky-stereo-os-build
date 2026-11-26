#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: gimp 3.2.8-1+stereo3d2+lc1 (queue row 137 with row 148, the stereo GIMP's milestone 2: depth layers),
# the successor of 3.2.8-1+stereo3d1+lc1 made by repo/lc-successor.py --in-place --overlay: the predecessor's debian/
# stays as it is (its changelog a byte identical suffix of the new one) but for this tree's Lean Code toolkit and the
# overlay: the two depth layers' patches after the series, debian/control (Build-Depends libstereo-policy-dev, the
# depth layers' model; gimp Recommends gimp-stereo-pictures, which exports MPO, JPS and PNS) and debian/copyright (the
# new files). Nothing is built here: release/build-from-lc-dsc.sh builds the .dsc (build.sh does both).
#   make-source-2.sh PREVIOUS OUT IMAGE
#   PREVIOUS  a folder with gimp_3.2.8-1+stereo3d1+lc1.dsc, its Debian tarball and gimp_3.2.8.orig.tar.xz
#   OUT       an empty folder: receives the new .dsc and Debian tarball and the orig tarball
#   IMAGE     an image with dpkg-dev and python3 (the build image)
# The date of the source is this folder's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^#   make-source-2/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
PREV=$(realpath "$1") OUT=$(mkdir -p "$2" && cd "$2" && pwd) IMG=$3
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")}
(cd "$PREV" && sha256sum --check --quiet --ignore-missing "$HERE/source-stereo3d1.sha256")
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-gimp}-source2-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$PREV":/prev:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cd "$W"
	cp /prev/gimp_3.2.8-1+stereo3d1+lc1.dsc /prev/gimp_3.2.8-1+stereo3d1+lc1.debian.tar.xz /prev/gimp_3.2.8.orig.tar.xz .
	dpkg-source -x --skip-patches gimp_3.2.8-1+stereo3d1+lc1.dsc prev >/dev/null
	mkdir -p overlay/patches
	for p in stereo3d-depth-layers.patch stereo3d-depth-layers-po.patch; do
		cp "/recipe/patches/$p" overlay/patches/
	done
	cp prev/debian/patches/series overlay/patches/series
	[ -z "$(tail -c1 overlay/patches/series)" ] || echo >> overlay/patches/series
	printf "%s\n" stereo3d-depth-layers.patch stereo3d-depth-layers-po.patch >> overlay/patches/series
	python3 - prev/debian/control overlay/control <<"CONTROL"
import sys
from pathlib import Path
s = Path(sys.argv[1]).read_text()
def sub(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)
# the depth layers'"'"' model and each eye'"'"'s move: the stereo policy library
sub("               libgtk-3-dev (>= 3.24.52-3+stereo3d1~),\n",
    "               libgtk-3-dev (>= 3.24.52-3+stereo3d1~),\n               libstereo-policy-dev (>= 1.24.0),\n")
# MPO, JPS and PNS from a stereo image and from depth layers are the stereo pictures plug-in'"'"'s
sub("         kscreen,\nRecommends: ghostscript,\n", "         kscreen,\nRecommends: ghostscript,\n            gimp-stereo-pictures,\n")
Path(sys.argv[2]).write_text(s)
CONTROL
	python3 - prev/debian/copyright overlay/copyright <<"COPYRIGHT"
import sys
from pathlib import Path
s = Path(sys.argv[1]).read_text()
anchor = "\nFiles: plug-ins/python/python-console/*\n"
assert s.count(anchor) == 1
stanza = """
Files: app/core/gimpdepthlayer.c app/core/gimpdepthlayer.h app/core/gimpeyeprojectable.c app/core/gimpeyeprojectable.h app/display/gimpdisplayshell-depth.c app/display/gimpdisplayshell-depth.h app/operations/gimpoperationdepthshift.c app/operations/gimpoperationdepthshift.h app/pdb/depth-layer-cmds.c pdb/groups/depth_layer.pdb
Copyright: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
License: GPL-3+
"""
Path(sys.argv[2]).write_text(s.replace(anchor, stanza + anchor))
COPYRIGHT
	grep -q "^License: GPL-3+$" overlay/copyright
	mkdir -p "$W/successor"
	PYTHONPATH=/toolkit python3 /toolkit/repo/lc-successor.py --work "$W/successor" --in-place --overlay overlay --reapply-patches --next 3.2.8-1+stereo3d2 \
		--item "Sparky Stereo OS: depth layers (queue row 148, the stereo GIMP'"'"'s milestone 2; stereo3d-depth-layers). A depth layer is a layer group that holds its layers at one depth the artist sets, in pixels of separation with three decimals, positive behind the screen, never clamped; each eye sees it moved by half the depth (a copy for a whole move, the stereo policy library'"'"'s resampling for a fractional one) and the stereo canvas shows each eye'"'"'s picture. Layers in no depth layer are at the screen and a 2D image is drawn as before; depth layers inside each other are each at their own value. Layer > New Depth Layer; the Depth row of the Layers dock; the keys 8 (pop) and 7 (sink) held over the canvas while the pointer moves, rebindable; the PDB procedures gimp-depth-layer-new, -get-depth, -set-depth and -new-from-eye. An XCF keeps the depth as the group'"'"'s parasite gimp-depth-layer, so another GIMP opens a plain layer group." \
		--item "The strings in nine languages besides English (stereo3d-depth-layers-po)." \
		--item "debian/control: Build-Depends libstereo-policy-dev (>= 1.24.0); gimp Recommends gimp-stereo-pictures." \
		--item "debian/copyright: the new files." \
		--source-date-epoch "$SOURCE_DATE_EPOCH" gimp_3.2.8-1+stereo3d1+lc1.dsc /out
	cp gimp_3.2.8.orig.tar.xz /out/
'
ls -la "$OUT"
