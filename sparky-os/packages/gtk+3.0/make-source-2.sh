#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: gtk+3.0 3.24.52-3+stereo3d2+lc1 (queue row 137, GIMP milestone 3: the deep and HDR canvas), the
# successor of 3.24.52-3+stereo3d1+lc1 made by repo/lc-successor.py --in-place --overlay: the predecessor's debian/ stays
# as it is (its changelog a byte identical suffix of the new one) but for this tree's Lean Code toolkit and the overlay:
# the two new patches after the series (stereo3d-gtkglarea-deep-surface, stereo3d-testsuite-glarea-volume) and
# debian/libgtk-3-0t64.symbols with the eight new symbols of libgtk-3.so.0 at this version (dh_makeshlibs runs
# dpkg-gensymbols with -c4, which fails on a symbol not listed). Nothing is built here: release/build-from-lc-dsc.sh builds
# the .dsc (build.sh does both).
#   make-source-2.sh PREVIOUS OUT IMAGE
#   PREVIOUS  a folder with gtk+3.0_3.24.52-3+stereo3d1+lc1.dsc, its Debian tarball and gtk+3.0_3.24.52.orig.tar.xz
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
docker run --rm --pull=never --name "${SPARKY_CONTAINER_PREFIX:-gtk3}-source2-$$" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME='Daniel Ramos (Capitain Jack)' -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$HERE":/recipe:ro -v "$PREV":/prev:ro -v "$OUT":/out "$IMG" bash -c '
	set -euo pipefail
	W=$(mktemp -d)
	cd "$W"
	cp /prev/gtk+3.0_3.24.52-3+stereo3d1+lc1.dsc /prev/gtk+3.0_3.24.52-3+stereo3d1+lc1.debian.tar.xz /prev/gtk+3.0_3.24.52.orig.tar.xz .
	dpkg-source -x --skip-patches gtk+3.0_3.24.52-3+stereo3d1+lc1.dsc prev >/dev/null
	mkdir -p overlay/patches
	for p in stereo3d-gtkglarea-deep-surface.patch stereo3d-testsuite-glarea-volume.patch; do
		cp "/recipe/patches/$p" overlay/patches/
	done
	cp prev/debian/patches/series overlay/patches/series
	[ -z "$(tail -c1 overlay/patches/series)" ] || echo >> overlay/patches/series
	printf "%s\n" stereo3d-gtkglarea-deep-surface.patch stereo3d-testsuite-glarea-volume.patch >> overlay/patches/series
	python3 - prev/debian/libgtk-3-0t64.symbols overlay/libgtk-3-0t64.symbols <<"SYMBOLS"
import sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text().splitlines(keepends=True)
version = "3.24.52-3+stereo3d2"
names = """gtk_gl_area_get_content_light_levels gtk_gl_area_get_luminances gtk_gl_area_get_mastering_display
    gtk_gl_area_get_surface_error gtk_gl_area_get_surface_shown gtk_gl_area_set_content_light_levels
    gtk_gl_area_set_luminances gtk_gl_area_set_mastering_display""".split()
heads = [i for i, l in enumerate(lines) if not l.startswith((" ", "*", "|", "#")) and l.strip()]
start = next(i for i in heads if lines[i].startswith("libgtk-3.so.0 "))
end = next((i for i in heads if i > start), len(lines))
out = list(lines)
for name in sorted(names):
    assert not any(l.split("@")[0].strip() == name for l in lines[start:end]), name
    entry = " %s@Base %s\n" % (name, version)
    block = [i for i in range(start + 1, end) if lines[i].startswith(" ") and "@" in lines[i]]
    after = next((i for i in block if lines[i].split("@")[0].strip() > name), end)
    out.insert(out.index(lines[after]) if after < end else out.index(lines[end - 1]) + 1, entry)
Path(sys.argv[2]).write_text("".join(out))
SYMBOLS
	for n in gtk_gl_area_get_surface_error gtk_gl_area_set_luminances gtk_gl_area_set_mastering_display; do
		grep -q "^ $n@Base 3.24.52-3+stereo3d2$" overlay/libgtk-3-0t64.symbols
	done
	mkdir -p "$W/successor"
	PYTHONPATH=/toolkit python3 /toolkit/repo/lc-successor.py --work "$W/successor" --in-place --overlay overlay --reapply-patches --next 3.24.52-3+stereo3d2 \
		--item "Sparky Stereo OS: a plain GtkGLArea'"'"'s deep picture on a surface of its own (queue row 137, GIMP milestone 3, the deep and HDR canvas; stereo3d-gtkglarea-deep-surface). An area that does not ask for stereo and whose format is deeper than 8 bits, whose colour state is not sRGB, or which carries luminances or mastering data hands its picture to the compositor on the stereo area'"'"'s own kind of surface, with nothing declared, so that its depth and description reach the compositor; surface-shown and surface-error say whether it does and why not (an X window, a compositor without colour management). On Wayland the picture goes as a dma-buf where one carries it and otherwise through memory, a wl_shm buffer as deep as the picture (XBGR16161616, XBGR2101010, XBGR16161616F, XBGR8888 or XRGB8888): every bit of a 16 bit picture on drivers that export no 16 bit dma-buf, and a way at all for a software renderer; GDK_WAYLAND_GL_AREA_MEMORY chooses. gtk_gl_area_set_luminances(), gtk_gl_area_set_mastering_display() and gtk_gl_area_set_content_light_levels() carry the protocol'"'"'s luminances, mastering display and content light levels." \
		--item "The testsuite checks the new functions and a plain 16 bit area on X11 (stereo3d-testsuite-glarea-volume)." \
		--item "debian/libgtk-3-0t64.symbols: the eight new symbols of libgtk-3.so.0." \
		--source-date-epoch "$SOURCE_DATE_EPOCH" gtk+3.0_3.24.52-3+stereo3d1+lc1.dsc /out
	cp gtk+3.0_3.24.52.orig.tar.xz /out/
'
ls -la "$OUT"
