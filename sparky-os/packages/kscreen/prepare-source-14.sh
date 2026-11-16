#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
# Usage: prepare-source-14.sh STAGED_SOURCE_DIR OUT TOOLKIT
# The successor of the +stereo3d13 source that publication round r1116a carries: Display Settings' two 3D switches
# (Anaglyph and Other stereo formats) and their help texts in Spanish (ORDER 507b).
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
printf '%s  %s\n' 1416a03265f229ecfb0d678ec8d7b164e13c6ca1bff3a3123ed1718c6d5f9aab "$input/kscreen_6.7.4-1+stereo3d13+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-1+stereo3d14 --source-date-epoch 1794787200 \
    --overlay "$HERE/overlay-stereo3d14" --item 'Spanish for the two 3D switches of Display Settings, Anaglyph and Other stereo formats, and their help texts (ORDER 507b).' \
    "$input/kscreen_6.7.4-1+stereo3d13+lc1.dsc" "$out"
