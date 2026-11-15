#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# kwin 4:6.7.4-2+stereo3d58+lc1: the staged +57 source (ORDER 567, which holds +56 and +55) and overlay-stereo3d58, the loading
# screen of every screen at the screen and awake (ORDER 571).
# Usage: prepare-source-58.sh STAGED_SOURCE_DIR OUT TOOLKIT   (SOURCE_DATE_EPOCH: the recipe's date)
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set it to the date of the recipe, repo/reproducible.py epoch RECIPE}"
printf '%s  %s\n' 3fcb1ee20630a843f68dfc4374e1f113ac640126f4c32810d23fdfba1eb81eef "$input/kwin_6.7.4-2+stereo3d57+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d58 --source-date-epoch "$SOURCE_DATE_EPOCH" \
    --overlay "$HERE/overlay-stereo3d58" \
    --item 'The desktop'"'"'s loading screen shows depth on every 3D screen (ORDER 571). KSplash maps one layer-shell surface per screen in the overlay layer, over the whole output, each taking the keyboard as it maps; Stereo KWin took the ones without the focus for windows of the pile, drawn whole behind the screen and asleep, so on two 3D screens one loading screen sank and stayed flat. A surface of the overlay layer that covers its output is now at the screen and awake, as the lock screen is (s58-0001); a smaller one keeps the role it had. Test: testStereoDepthLoadingScreen (s58-0002).' \
    --item 'Carry the complete staged +stereo3d57 source, which holds +stereo3d56 and +stereo3d55.' \
    "$input/kwin_6.7.4-2+stereo3d57+lc1.dsc" "$out"
