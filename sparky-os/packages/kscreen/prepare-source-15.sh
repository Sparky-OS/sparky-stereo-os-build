#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-15.sh PUBLISHED_14_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' f7f4315456985ad586a9e46127e8475d81bafe1dd48828e5566055a63f143b5f "$input/kscreen_6.7.4-1+stereo3d14+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-1+stereo3d15 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d15" \
 --item 'Offer the per-output eye selector while its current replica group composes stereo; keep it disabled with a reason otherwise. Explain the 2D screen selection and translate both new messages in the ten required languages. No libkscreen or protocol change (ORDER 763).' \
 "$input/kscreen_6.7.4-1+stereo3d14+lc1.dsc" "$out"
