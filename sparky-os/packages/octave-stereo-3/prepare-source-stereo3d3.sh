#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/23. Copyright 2026 under the GNU GPL3 License.
# Sparky Stereo OS, row 50 step 5: the source of octave 11.3.0-1+stereo3d3+lc1, the successor of the published
# 11.3.0-1+stereo3d2+lc1 (round r1118a; Debian testing and unstable carry 11.3.0-1, the same base): its debian/ kept,
# overlay-stereo3d3/ adds patch 0004 (each 3D axes of a stereo figure fitted to the person's depth limits, the stereo
# format on the drawing area only, Enable 3D and the display settings in the figure's Tools menu), the whole series, the
# edition's site files (the default of Enable 3D in octaverc, the sentences in ten languages, the welcome example) and
# the list of our files for the copyright file; --depends adds libstereo-declare-dev, pkgconf and qt6-base-private-dev
# to Build-Depends, in the alphabetical place, and ${qt6:private-abi} to the octave package's Depends (set by the
# overlay's debian/rules, the published one with that substitution beside octave-abi), and changes nothing else of
# debian/control.
# Usage: prepare-source-stereo3d3.sh PUBLISHED_DIR OUT TOOLKIT   (SOURCE_DATE_EPOCH: the recipe's date)
set -euo pipefail
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1"); out=$(realpath -m "$2"); toolkit=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set the recipe date}"
printf '%s  %s\n' ef6f2dbdc55faf32e5c740968f91075e605f66054bb8cb58994867090e35c204 \
	"$input/octave_11.3.0-1+stereo3d2+lc1.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 11.3.0-1+stereo3d3 \
	--source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$HERE/overlay-stereo3d3" \
	--depends '               libsndfile1-dev,
' '               libsndfile1-dev,
               libstereo-declare-dev (>= 1.12.2),
' \
	--depends '               portaudio19-dev,
' '               pkgconf,
               portaudio19-dev,
' \
	--depends '               qt6-tools-dev,
' '               qt6-base-private-dev,
               qt6-tools-dev,
' \
	--depends 'Package: octave
Architecture: any
Depends: ${shlibs:Depends},
' 'Package: octave
Architecture: any
Depends: ${shlibs:Depends},
         ${qt6:private-abi},
' \
	--item 'A stereo figure is fitted to the person'"'"'s depth limits, read through libstereo-declare 1.12.2 for the figure'"'"'s window: each 3D axes gets the largest separation under which every pixel of it stays inside them, measured in a pass from the camera between the eyes, and a live change of the limits redraws an open figure (row 50 step 5). Build-Depends: libstereo-declare-dev (>= 1.12.2), pkgconf, qt6-base-private-dev.' \
	--item 'The figure property stereoeyeseparation stays readable and settable and no longer decides the depth; a script that sets it is told once, in the command window.' \
	--item 'Enable 3D is on by default: the site octaverc sets the default of the figure property stereo from the preference sparky_stereo/enable_3d, which each figure'"'"'s Tools menu changes (it applies to new figures), beside an entry that opens the desktop'"'"'s 3D display settings.' \
	--item 'Only the figure'"'"'s drawing area asks for stereo buffers: the figure window stays one picture, the same in both eyes. When the depth limits are not offered, do not arrive or cannot be read, or a figure gets no stereo buffers, the command window says so once.' \
	--item 'The welcome example, the menu entries and every sentence told are in ten languages; the example follows Enable 3D and the fitted depth instead of a separation of its own.' \
	--item 'octave depends on the Qt private ABI it was built with (qt6-base-private-abi), since the figure reads the window system'"'"'s handles through Qt'"'"'s private QPlatformNativeInterface; debian/rules sets it beside the octave-abi Provides.' \
	"$input/octave_11.3.0-1+stereo3d2+lc1.dsc" "$out"
