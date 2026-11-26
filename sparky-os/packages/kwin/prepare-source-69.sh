#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-69.sh STAGED_68_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
# STAGED_68_DIR holds the staged kwin_6.7.4-2+stereo3d68+lc1 source (row 132's stage: dsc, debian tarball, orig and its signature).
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 1fe763923dca2923cb7580714e481430470f7e7fd1e0d1a537fceea5272e4bd9 "$input/kwin_6.7.4-2+stereo3d68+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d69 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d69" \
 --item 'The person'"'"'s element limit (kwinrc [StereoDepth] ElementLimit, 1 pixel of a view 1920 wide by default), how far an element drawn inside a window may lie in front of or behind what it lies on, is an option of KWin and is told to every surface that follows its depth: version 7 of kde_stereo_content_v1, the event element_limit, before output_width and depth_limits, again when it changes; no display factor is applied to it (queue row 121). Qt Widgets takes its step of depth inside a window from it.' \
 --item 'Tests: testElementLimit in testStereoDepthExchange, red on +68; the test'"'"'s init() checked the manager'"'"'s version against 5 since version 6, so every function of that test failed at init (queue row 910).' \
 "$input/kwin_6.7.4-2+stereo3d68+lc1.dsc" "$out"
