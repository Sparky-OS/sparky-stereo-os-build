#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Usage: prepare-source-56.sh STAGED_SOURCE_DIR OUT TOOLKIT
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
printf '%s  %s\n' c8da53791f6cdcecd5d096331c599a88540047625b5efe02a6b0cfd1a9c0d40a "$input/kwin_6.7.4-2+stereo3d55+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d56 --source-date-epoch 1794713501 \
    --overlay "$HERE/overlay-stereo3d56" --item 'Preserve staged ORDER 567 +55 and carry interlaced scan type through the mode list, marking the height with i (ORDER 568).' \
    "$input/kwin_6.7.4-2+stereo3d55+lc1.dsc" "$out"
