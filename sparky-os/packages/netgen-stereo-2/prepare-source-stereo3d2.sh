#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23. Copyright 2026 under the GNU GPL3 License.
# Sparky Stereo OS, row 50 step 5: the source of netgen 6.2.2606+dfsg1-3+stereo3d2+lc1, the successor of the staged
# 6.2.2606+dfsg1-3+stereo3d1+lc1 (row 50 step 2, in the accepted pool of row 794): its debian/ kept, overlay-stereo3d2/
# adds patch 0004 (the drawing area fitted to the person's depth limits, Enable 3D), the whole series and the list of our
# files for the copyright file; --depends adds libstereo-declare-dev and pkgconf to Build-Depends, in the alphabetical
# place, and changes nothing else of debian/control.
# Usage: prepare-source-stereo3d2.sh STAGED_DIR OUT TOOLKIT   (SOURCE_DATE_EPOCH: the recipe's date; dpkg-dev, devscripts)
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1"); out=$(realpath -m "$2"); toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' bc077655c9bf6f9c0a50b2f8bfc4fefef69544575100e31c0dd5d60865c6fe9a \
	"$input/netgen_6.2.2606+dfsg1-3+stereo3d1+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 6.2.2606+dfsg1-3+stereo3d2 \
	--source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$HERE/overlay-stereo3d2" \
	--depends ' libswscale-dev,
' ' libstereo-declare-dev (>= 1.12.2),
 libswscale-dev,
' \
	--depends ' mpi-default-dev,
' ' mpi-default-dev,
 pkgconf,
' \
	--item 'The drawing area is drawn for each eye whenever the desktop offers a stereo picture: Enable 3D (View, Viewing Options; on by default, kept in ng.opt as stereo3d.enable) asks for the quad-buffer drawing area at the start, and a 2D desktop keeps the single picture with nothing said (row 50 step 5).' \
	--item 'The separation is fitted to the person'"'"'s depth limits, read through libstereo-declare 1.12.2 on the drawing area: the largest under which every pixel of it stays inside them. It replaces the constant 3 % and follows a live change of the limits. Build-Depends: libstereo-declare-dev (>= 1.12.2), pkgconf.' \
	--item 'Viewing Options has a button to the desktop'"'"'s 3D display settings; when the limits are not offered, do not arrive or cannot be read, the status bar says so once, in ten languages.' \
	"$input/netgen_6.2.2606+dfsg1-3+stereo3d1+lc1.dsc" "$out"
