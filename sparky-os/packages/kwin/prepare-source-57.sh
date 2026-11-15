#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# kwin 4:6.7.4-2+stereo3d57+lc1: the staged +56 source (ORDER 568, which holds +55) and overlay-stereo3d57, the
# on-screen keyboard shown only in tablet mode (ORDER 567, KWin merge request 8592 by Luca Tramonti).
# Usage: prepare-source-57.sh STAGED_SOURCE_DIR OUT TOOLKIT   (SOURCE_DATE_EPOCH: the recipe's date)
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set it to the date of the recipe, repo/reproducible.py epoch RECIPE}"
printf '%s  %s\n' b3a362b8f6d96febfe05b6e8d26aa515a5c56b06999c92e5c74c6040b17770e1 "$input/kwin_6.7.4-2+stereo3d56+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d57 --source-date-epoch "$SOURCE_DATE_EPOCH" \
    --overlay "$HERE/overlay-stereo3d57" \
    --item 'The on-screen keyboard shows only in tablet mode by default on a computer that has a tablet mode (ORDER 567; Daniel, 2026-11-14: "enable on screen keyboard on tablet mode"). Carried: KWin merge request 8592 by Luca Tramonti, "Option to limit Virtual Keyboard to Tablet Mode", open upstream, adapted to 6.7.4 (s57-0001): kwinrc, [Wayland] InputMethodTabletOnly, true by default, honored while tablet mode is available. The other behaviour, the keyboard on any touch, is the check box "Only when in Tablet Mode" of the Virtual Keyboard page switched off; in the nine translated languages (kwin-keyboard-tablet-mode-only.po.patch).' \
    --item 'For headless proofs, KWIN_VIRTUAL_TOUCH_SCREEN=1 gives a virtual session a built-in touch screen, so tablet mode is available (s57-0002). Carry the complete staged +stereo3d56 source, which holds +stereo3d55.' \
    "$input/kwin_6.7.4-2+stereo3d56+lc1.dsc" "$out"
