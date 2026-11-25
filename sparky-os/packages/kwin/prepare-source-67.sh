#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25. Copyright 2026 under the GNU GPL3 License.
# Usage: prepare-source-67.sh STAGED_66_DIR OUT TOOLKIT; SOURCE_DATE_EPOCH is the recipe's date.
# STAGED_66_DIR holds the staged kwin_6.7.4-2+stereo3d66+lc1 source (row 81's stage: dsc, debian tarball, orig and its signature).
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' 610824a58241c9bb1ddb4342a9d563f8073752e80362e27ea0d7a7032545bbc1 "$input/kwin_6.7.4-2+stereo3d66+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 4:6.7.4-2+stereo3d67 --source-date-epoch "$SOURCE_DATE_EPOCH" \
 --overlay "$HERE/overlay-stereo3d67" \
 --item 'A touch on a text field that already has the focus asks for the on-screen keyboard again: KWin says it on D-Bus (org.kde.kwin.VirtualKeyboard.showRequested), so a keyboard that is not the input method (Plasma Keyboard as the keyboard of Fcitx 5, in the Japanese, Korean and Chinese sessions) shows for it as KWin own keyboard does (queue row 71).' \
 --item 'org.kde.kwin.VirtualKeyboard.setOnScreenKeyboardShown(bool): while such a keyboard says it is shown, its layer-shell window, found by the calling process, keeps the focused window clear of it as KWin own input panel does (the window ends where the keys begin and gets its place back), and text-input v2 hears the overlap.' \
 --item 'Only KWin own input method binds the input-method protocols again (Vlad Zahorodnii, merge request 9601, backported to 6.7.4): a second input method started behind KWin back can no longer take the input panel.' \
 --item 'Tests: testInputMethod gains testShowRequestedOnFocusedField and testOnScreenKeyboardKeepsFieldInView, red on +66.' \
 "$input/kwin_6.7.4-2+stereo3d66+lc1.dsc" "$out"
