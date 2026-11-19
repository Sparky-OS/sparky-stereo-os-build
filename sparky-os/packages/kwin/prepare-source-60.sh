#!/bin/bash
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?the recipe date}"
python3 "$toolkit/repo/lc-successor.py" --in-place --reapply-patches --next 4:6.7.4-2+stereo3d60 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d60" \
 --item 'Carry stereo content protocol 6: the pixel width of the output KWin already selects precedes each depth_limits event, including equal-limit output changes. Keep the levels, stacks, limits and older protocol resources unchanged (ORDER 750e).' \
 "$input/kwin_6.7.4-2+stereo3d59+lc1.dsc" "$out"
