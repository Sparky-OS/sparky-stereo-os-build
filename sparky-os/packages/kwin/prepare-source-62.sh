#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-62.sh STAGED_61_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 791bd63fc46514b64e781bc5c20147033995135c38da9b7bf674b9f6d6c7e3c9 "$input/kwin_6.7.4-2+stereo3d61+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d62 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d62" \
 --item 'Return both complete eyes for every screenshot of a composing output, including ordinary windows, and report composing output mode separately from paired content through ScreenShot2 version 7 (ORDER 772).' \
 --item 'Retain the complete +stereo3d61 source and replica composition behavior; carry the accepted screenshot reply autotests and upstream context fixes with their author credit.' \
 "$input/kwin_6.7.4-2+stereo3d61+lc1.dsc" "$out"
