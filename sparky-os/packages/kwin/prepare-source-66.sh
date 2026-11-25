#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-66.sh STAGED_65_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
# STAGED_65_DIR holds the staged kwin_6.7.4-2+stereo3d65+lc1 source (dsc, debian tarball, orig and its signature).
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 07323dd5b35772ff21b039d0810ee0ee67f3531423ebb5e26d7ba2b3ca36bb31 "$input/kwin_6.7.4-2+stereo3d65+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d66 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d66" \
 --item 'A network screen (an output made for a device on the network, such as a Cast device) is a screen like the others: it offers the 3D formats and the eye swap of a monitor in Display Settings, arrives in 2D at the device mode, and the 3D format the person chose for that device comes back at the next Throw to it (queue row 81).' \
 --item 'The stream of a network screen is that output picture: its eyes packed side by side or top and bottom, or mixed as an anaglyph, as the format chosen for it does, with its eye swap, and a format chosen while it streams reaches the stream at once; in 2D one view. The anaglyph matrices are shared with the screens own layer.' \
 --item 'The window menu keeps Move to Screen for the computer own screens and lists the network screens under Throw to, by their device names, in ten languages.' \
 --item 'Tests: test_virtual_output_properties, screencasting_test and the new testThrowToMenu hold each of these; the split-eye rows of the phone headset are unchanged.' \
 "$input/kwin_6.7.4-2+stereo3d65+lc1.dsc" "$out"
