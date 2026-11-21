#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-64.sh STAGED_63_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' af15129d549d0709ebd9b32168f942b9925c4662d10ec74514dfd95c48735646 "$input/kwin_6.7.4-2+stereo3d63+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d64 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d64" \
 --item 'Ship the nine translated KWin catalogues, including Spanish stereo depth and the accepted Throw and Catch names (ORDER 762).' \
 --item 'Retain +stereo3d63 code and tests unchanged. Keep its keyboard and eight-language wallpaper patches; ORDER 46b supplies the missing Spanish wallpaper entries too.' \
 "$input/kwin_6.7.4-2+stereo3d63+lc1.dsc" "$out"
