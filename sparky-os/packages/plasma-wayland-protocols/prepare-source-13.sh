#!/bin/bash
# Sparky Stereo OS: the +stereo3d13+lc1 source of plasma-wayland-protocols (queue row 121) from the published +stereo3d12+lc1
# source: overlay-stereo3d13 adds s13-0001 (kde_stereo_content_v1 version 7, the element_limit event).
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-13.sh INPUT_DIR OUT_DIR TOOLKIT   (INPUT_DIR holds the +12+lc1 .dsc and its files; TOOLKIT is sparky-os)
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$toolkit/repo/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
python3 "$toolkit/repo/lc-successor.py" --in-place --reapply-patches --next 1.21.0-1+stereo3d13 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d13" \
 --item 'Carry stereo content protocol 7: kde_stereo_depth_v1 tells a surface the user'"'"'s element limit (element_limit, pixels of a view 1920 wide), the step of depth inside a window, before output_width and depth_limits. Keep every request and event of the earlier versions (queue row 121).' \
 "$input/plasma-wayland-protocols_1.21.0-1+stereo3d12+lc1.dsc" "$out"
