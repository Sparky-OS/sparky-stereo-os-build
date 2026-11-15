#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Usage: prepare-source-55.sh PUBLISHED_SOURCE_DIR OUT TOOLKIT
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
printf '%s  %s\n' 3663e48d747feeec0d348800ec8ce17130734abef6969640510c51d8b9903d33 "$input/kwin_6.7.4-2+stereo3d54+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d55 --source-date-epoch 1794614400 \
    --overlay "$HERE/overlay-stereo3d55" --item 'Carry interlaced scan type through the mode list; mark the height with i and preserve the selected scan type (ORDER 568).' \
    "$input/kwin_6.7.4-2+stereo3d54+lc1.dsc" "$out"
