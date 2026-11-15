#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Usage: prepare-source-11.sh PUBLISHED_SOURCE_DIR OUT TOOLKIT
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
printf '%s  %s\n' 02e47e16d676d1629af407442e393b386d9d9bc23d346aeda196a1f57dd34094 "$input/plasma-wayland-protocols_1.21.0-1+stereo3d10+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 1.21.0-1+stereo3d11 --source-date-epoch 1794614400 \
    --overlay "$HERE/overlay-stereo3d11" --item 'Carry interlaced scan type through the mode list; mark the height with i and preserve the selected scan type (ORDER 568).' \
    "$input/plasma-wayland-protocols_1.21.0-1+stereo3d10+lc1.dsc" "$out"
