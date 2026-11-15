#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Usage: prepare-source-13.sh PUBLISHED_SOURCE_DIR OUT TOOLKIT
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
printf '%s  %s\n' d1f7ea741b059318d03107a6b6ac6d29eb56fe256569d0a0044c57813e3a8aa1 "$input/kscreen_6.7.4-1+stereo3d12+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-1+stereo3d13 --source-date-epoch 1794614400 \
    --overlay "$HERE/overlay-stereo3d13" --item 'Carry interlaced scan type through the mode list; mark the height with i and preserve the selected scan type (ORDER 568).' \
    "$input/kscreen_6.7.4-1+stereo3d12+lc1.dsc" "$out"
