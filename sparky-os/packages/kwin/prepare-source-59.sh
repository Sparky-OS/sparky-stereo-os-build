#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# kwin 4:6.7.4-2+stereo3d59+lc1: the published +58 source and overlay-stereo3d59, the depth limits on every declared child window (ORDER 17, milestone 5 round 2).
# Usage: prepare-source-59.sh STAGED_SOURCE_DIR OUT TOOLKIT   (SOURCE_DATE_EPOCH: the recipe's date)
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set it to the date of the recipe, repo/reproducible.py epoch RECIPE}"
printf '%s  %s\n' 1169f6d45c9e5e9c2074dd758f3b398791973d4741eb6d2530ea8303706a7af0 "$input/kwin_6.7.4-2+stereo3d58+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d59 --source-date-epoch "$SOURCE_DATE_EPOCH" \
    --overlay "$HERE/overlay-stereo3d59" \
    --item 'The depth limits reach a declared child window (ORDER 17). s52-0001 wrote _KDE_NET_WM_STEREO_DEPTH_LIMITS on the window that declares stereo content only; a program whose 3D area is a child window (listed in _KDE_NET_WM_STEREO_CONTENT_CHILDREN) declares on the child, so the property never reached the window it reads and libstereo-declare answered -ENODATA. KWin now writes the two limits on each tracked child that holds stereo content, at the declaration, at every change of the limits or of the output and when the children change, and removes them when the declaration or the child goes; the announced support version is 11, so a program knows the property comes on its child and that its arrival means KWin holds the child (s59-0001). Test: testStereoChildWindowDepthLimits, red on +58 and green on +59 (s59-0002).' \
    --item 'A declared Wayland subsurface that asks for kde_stereo_depth_v1 after its window is shown now gets the limits of the output at once: the depth states of a window are made from its top-level surface, whose follow was the only one that scheduled the update (s59-0003). Test: testLimitsOnDeclaredSubsurface, red on +58 and green on +59 (s59-0004).' \
    --item 'Carry the complete published +stereo3d58 source.' \
    "$input/kwin_6.7.4-2+stereo3d58+lc1.dsc" "$out"
