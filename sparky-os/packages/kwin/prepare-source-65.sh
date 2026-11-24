#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/24. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-65.sh PUBLISHED_64_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
# PUBLISHED_64_DIR holds the published kwin_6.7.4-2+stereo3d64+lc1 source (dsc, debian tarball, orig and its signature).
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 974723f18fab298a1021a26e8b5b8315608efc6d96efdf3ef2b1fda628594574 "$input/kwin_6.7.4-2+stereo3d64+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d65 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d65" \
 --item 'A window that went with Xwayland is never kept: when Xwayland goes away the compositor says that no window is active, and the translucency effect forgets a deleted window and handles the newly selected window first, so the selected window is opaque again (queue row 862).' \
 --item 'When KWin finds Xwayland gone, the person is told once, in ten languages, through sparky-stereo-problems, which X11 programs closed with it, why and what to do; the notice ends at the next start.' \
 --item 'Tests: testTranslucencyXwayland and the Xwayland crash test check the selected window and the compositor signal after Xwayland went away.' \
 "$input/kwin_6.7.4-2+stereo3d64+lc1.dsc" "$out"
