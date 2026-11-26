#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-14.sh INPUT_DIR OUT_DIR TOOLKIT
# INPUT_DIR holds the milestone 1 +13+lc1 source closure. TOOLKIT is sparky-os.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$toolkit/repo/reproducible.py" epoch "$here")}
export SOURCE_DATE_EPOCH
python3 "$toolkit/repo/lc-successor.py" --in-place --reapply-patches --next 1.21.0-1+stereo3d14 \
    --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$here/overlay-stereo3d14" \
    --item 'Send separate behind and in-front element steps for the selected display in protocol version 7 (row 121).' \
    "$input/plasma-wayland-protocols_1.21.0-1+stereo3d13+lc1.dsc" "$out"
