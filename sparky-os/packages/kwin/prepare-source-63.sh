#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-63.sh STAGED_62_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 256704b93d77a27efe2edb3517e0a22a0f8f48939d603c3a8d77e37a87a4a3c5 "$input/kwin_6.7.4-2+stereo3d62+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d63 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d63" \
 --item 'Apply the phone output eye-swap setting once in both split-eye screencast paths (ORDER 762).' \
 --item 'Retain the complete +stereo3d62 source and DRM output conversion; extend native-panel and mirrored-panel screencast tests with swapped-eye rows.' \
 "$input/kwin_6.7.4-2+stereo3d62+lc1.dsc" "$out"
