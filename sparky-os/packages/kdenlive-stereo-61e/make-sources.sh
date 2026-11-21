#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# ORDER 61e: the next sources of our MLT (7.40.0-1+stereo3d8) and Kdenlive (26.08.1-1+stereo3d9), from the published +lc1 sources
# of round r1118a (mlt +stereo3d6, kdenlive +stereo3d6), each with this folder's patches put after the published series
# (repo/lc-successor.py --in-place --overlay --reapply-patches, which applies the whole new series), Kdenlive with the
# edition's catalogue patches last (sparky-os/translations: ORDER 46c's, then 61e's) and its libmlt7 dependency raised to
# the MLT it needs (stereo3d_unpack as a producer's first filter).
# Usage: make-sources.sh WORK PUBLISHED_POOL IMAGE
#   WORK            an empty folder: published-*/ (the copied published sources), source-mlt/, source-kdenlive/ (the new .dsc)
#   PUBLISHED_POOL  the published tree's pool/main (its m/mlt and k/kdenlive folders are read)
#   IMAGE           an image with dpkg-dev, quilt and python3 (the build image)
# The date of both sources is this folder's last commit (repo/reproducible.py), never the clock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || { sed -n '/^# Usage/,/^# The date/p' "$0" | sed 's/^# \?//' >&2; exit 2; }
WORK=$(mkdir -p "$1" && cd "$1" && pwd) POOL=$(realpath "$2") IMG=$3
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
EPOCH=$(python3 "$TOP/repo/reproducible.py" epoch "$HERE")
copy_published() {  # dsc and every file it names, checked against the .dsc's own checksums
	local dsc=$1 dest=$2
	mkdir -p "$dest"
	cp "$dsc" "$dest/"
	python3 - "$dsc" "$dest" <<'PY'
import hashlib, shutil, sys
from pathlib import Path
dsc, dest = Path(sys.argv[1]), Path(sys.argv[2])
for line in dsc.read_text().split('Checksums-Sha256:\n', 1)[1].splitlines():
    if not line.startswith(' '):
        break
    digest, size, name = line.split()
    assert hashlib.sha256((dsc.parent / name).read_bytes()).hexdigest() == digest, name
    shutil.copyfile(dsc.parent / name, dest / name)
PY
}
copy_published "$POOL/m/mlt/mlt_7.40.0-1+stereo3d6+lc1.dsc" "$WORK/published-mlt"
copy_published "$POOL/k/kdenlive/kdenlive_26.08.1-1+stereo3d6+lc1.dsc" "$WORK/published-kdenlive"
mkdir -p "$WORK/overlay-mlt" "$WORK/overlay-kdenlive" "$WORK/source-mlt" "$WORK/source-kdenlive"
cp -r "$HERE/overlay-mlt/." "$WORK/overlay-mlt/"
cp -r "$HERE/overlay-kdenlive/." "$WORK/overlay-kdenlive/"
cp "$TOP/translations/kdenlive-order46c-catalogues.patch" "$TOP/translations/kdenlive-order61e.po.patch" "$WORK/overlay-kdenlive/patches/"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:-kdenlive-stereo-61e}-sources" --ulimit core=1 --network none --platform linux/amd64 \
	--user "$(id -u):$(id -g)" -e HOME=/tmp -e SOURCE_DATE_EPOCH="$EPOCH" -e DEBFULLNAME="Daniel Ramos (Capitain Jack)" -e DEBEMAIL=Capitain_Jack@yahoo.com \
	-v "$TOP":/toolkit:ro -v "$WORK":/work "$IMG" bash -c '
	set -euo pipefail
	cd /tmp
	python3 /toolkit/repo/lc-successor.py --in-place --overlay /work/overlay-mlt --reapply-patches --next 7.40.0-1+stereo3d8 \
		--item "stereo3d_unpack can be the first filter of a producer (in_producer, ORDER 61e): it takes the views of a 3D clip out of the producer'"'"'s own picture and fits each to its half of a frame of the profile'"'"'s size, the left eye in the left half, so an editor'"'"'s project of clips with different packings has full side by side frames; target_views=half for a profile whose views are half width (patch 0013)." \
		--item "The avformat consumer writes the frame packing arrangement SEI of an HEVC stream through FFmpeg'"'"'s hevc_metadata (frame_packing=insert) when stereo3d is set and the encoder does not write it itself, as libx265 does not (patch 0014)." \
		--item "stereo3d_unpack keeps a deep source'"'"'s bits: asked for more than 8 bits a sample it works the views in RGBA64 and hands back the format asked for, an opaque picture without an alpha mask (patch 0015)." \
		--item "stereo3d_unpack judges half or whole views by the producer'"'"'s own frame, not by a player'"'"'s frame fitted to its profile (patch 0016)." \
		--work /tmp --source-date-epoch "$SOURCE_DATE_EPOCH" /work/published-mlt/mlt_7.40.0-1+stereo3d6+lc1.dsc /work/source-mlt
	python3 /toolkit/repo/lc-successor.py --in-place --overlay /work/overlay-kdenlive --reapply-patches --next 26.08.1-1+stereo3d9 \
		--item "The monitors show a 3D video in 3D by default where the compositor takes stereo content (Daniel, 2026-10-14: \"Kdenlive 3D preview on by default on a stereo desktop: YES\"; ORDER 61e, patch 0009); the person'"'"'s own choice is kept." \
		--item "Where the 3D preview cannot be shown the person is told once in the monitor and sees the packed frame (patch 0010)." \
		--item "Render presets in a Stereoscopic 3D group, H.264 and HEVC in MP4 and Matroska, write full side by side with the frame packing SEI and the container'"'"'s mark; a 2D project is refused with them (patch 0011)." \
		--item "In a 3D project each 3D clip'"'"'s views are taken out side by side in the timeline, so clips of different packings make one full side by side project (patch 0012)." \
		--item "Thumbnails of a 3D clip are its left eye'"'"'s view; a packing only the stream'"'"'s SEI says is learned from a decoded frame (patch 0013)." \
		--item "A 3D project'"'"'s resolution is one eye'"'"'s: a project of 1920x1080 renders 3840x1080, each eye a 1920x1080 picture, nothing squeezed (patch 0014)." \
		--item "Each video clip'"'"'s properties offer the stereo layer'"'"'s 3D Input Format and, for a clip shown in 3D, Swap left and right eyes and Save the correction into the file; the correction is kept in the project (patch 0015)." \
		--item "The monitors'"'"' 3D options are the layer'"'"'s Enable 3D, the left eye'"'"'s view and Display Settings; the project'"'"'s Right Eye First is moved to its clips once, and the person is told (patch 0016)." \
		--item "A command-line render with a preset name Kdenlive does not have stops and says so instead of writing the default preset'"'"'s format under the name given (patch 0017)." \
		--item "Both monitors show 3D at once: their 3D areas share the declaration library, which a process sets up once (patch 0018)." \
		--item "The edition'"'"'s catalogues of ORDER 46c (the +stereo3d7 recipe, carried here) and the Brazilian Portuguese of the sentences above. The +stereo3d8 of ORDER 61e'"'"'s first milestone was staged only and enters no round: this source carries it." \
		--depends "libmlt7 (>= 7.40.0-1+stereo3d5+lc1)" "libmlt7 (>= 7.40.0-1+stereo3d8+lc1)" \
		--work /tmp --source-date-epoch "$SOURCE_DATE_EPOCH" /work/published-kdenlive/kdenlive_26.08.1-1+stereo3d6+lc1.dsc /work/source-kdenlive'
cp "$WORK"/published-mlt/mlt_7.40.0.orig.tar.gz "$WORK/source-mlt/"
cp "$WORK"/published-kdenlive/kdenlive_26.08.1.orig.tar.xz* "$WORK/source-kdenlive/"
ls "$WORK"/source-mlt/*.dsc "$WORK"/source-kdenlive/*.dsc
