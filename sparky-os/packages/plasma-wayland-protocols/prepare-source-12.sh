#!/bin/bash
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?the recipe date}"
python3 "$toolkit/repo/lc-successor.py" --in-place --next 1.21.0-1+stereo3d12 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d12" \
 --item 'Carry stereo content protocol 6: the pixel width of the output KWin already selects precedes each depth_limits event, including equal-limit output changes. Keep the levels, stacks, limits and older protocol resources unchanged (ORDER 750e).' \
 "$input/plasma-wayland-protocols_1.21.0-1+stereo3d11+lc1.dsc" "$out"
