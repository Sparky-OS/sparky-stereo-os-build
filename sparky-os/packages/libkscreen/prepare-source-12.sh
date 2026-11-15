#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Usage: prepare-source-12.sh PUBLISHED_SOURCE_DIR OUT TOOLKIT
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
printf '%s  %s\n' ccc0012058ff5c57b821a70b6ae26c500b6b26995f05cbc8f5fcbaa698d50bdc "$input/libkscreen_6.7.4-1+stereo3d11+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-1+stereo3d12 --source-date-epoch 1794614400 \
    --overlay "$HERE/overlay-stereo3d12" --item 'Carry interlaced scan type through the mode list; mark the height with i and preserve the selected scan type (ORDER 568).' \
    "$input/libkscreen_6.7.4-1+stereo3d11+lc1.dsc" "$out"
