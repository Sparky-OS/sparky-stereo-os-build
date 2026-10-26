#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run inside the isolated package image; paths are supplied by the caller.
set -euo pipefail
export DEBEMAIL=Capitain_Jack@yahoo.com
export DEBFULLNAME='Daniel Ramos (Capitain Jack)'
export DEB_BUILD_OPTIONS=parallel=4
input=${1:?published source directory}
work=${2:?new build directory}
toolkit=${3:?edition sparky-os toolkit directory}
recipe=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$work"
cp "$input/bino_2.8.orig.tar.gz" "$input/bino_2.8.orig.tar.gz.asc" "$work/"
dpkg-source -x "$input/bino_2.8-1+stereo3d2+lc1.dsc" "$work/bino-2.8"
cd "$work/bino-2.8"
cp "$recipe/native-playback.patch" debian/patches/0006-native-playback.patch
printf '%s\n' 0006-native-playback.patch >> debian/patches/series
QUILT_PATCHES=debian/patches quilt push
# Refresh the existing distribution pipeline using its checked integration tool.
python3 - <<'PY'
from pathlib import Path
p=Path('debian/rules');s=p.read_text();marker='# Distribution-only processing; authored source remains in the source archive.'
assert s.count(marker)==1
p.write_text(s.split(marker)[0]+'''override_dh_auto_configure:
\tdh_auto_configure -- -DBINO_STEREO_DESKTOP=ON

override_dh_gencontrol:
\tdh_gencontrol -- -Vqt6:MultimediaVersion=$$(pkg-config --modversion Qt6Multimedia)

''')
p=Path('debian/control');s=p.read_text().replace(' libstereo-layer-dev (>= 1.5.0),', ''' libstereo-layer-dev (>= 1.5.0),
 libstereo-declare-dev (>= 1.7.0),
 libstereo-av-dev (>= 1.12.0-2+lc1),
 libwayland-dev,
 wayland-protocols,
 libegl-dev,
 libgl-dev,
 libxext-dev,
 qt6-base-private-dev,
 qt6-multimedia-private-dev (>= 6.11.2-3+stereo3d11+lc1),''')
s=s.replace(' libxcb-cursor0,',' libxcb-cursor0,\n libstereo-av1 (>= 1.12.0-2+lc1),\n libqt6multimedia6 (>= 6.11.2-3+stereo3d11+lc1),\n qt6-multimedia-private-abi (= ${qt6:MultimediaVersion}),\n qt6-svg-plugins,')
s=s.replace('3D video player (Sparky Stereo OS build: always OpenGL stereo output)','3D video player (Sparky Stereo OS native eye-pair build)')
s=s.replace(' It can output these videos for several types\n of anaglyph glasses or 3D displays.',' The stereo desktop receives each eye at its source resolution and\n handles the display format. Ordinary 2D playback remains available.')
p.write_text(s)
PY
rm -rf debian/sparky-lean-toolkit
dch --newversion 2.8-1+stereo3d7 --distribution unstable \
 'Make video and overlay double-click use the same fullscreen toggle as F11.' \
 'Opt into Qt Multimedia native raster delivery before playback; retain default behavior in the upstream-mode build.' \
 'Restore shared filename and shape guesses for unmarked files below every declaration, with per-file corrections retained.' \
 'Keep native samples and source pixel aspect, avoiding duplicate aspect correction from half-view guesses; retain all shared helper imports against published +3.' \
 'Keep upstream output modes behind BINO_STEREO_DESKTOP=OFF; the edition builds with ON.'
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare . 2.8-1+stereo3d7+lc1 --toolkit "$toolkit" \
 --preserve-source 'src/*.hpp' 'Qt moc consumes these authored declarations; preserve this additional consumer input.'
dpkg-buildpackage -S -us -uc -d
cd "$work"
dpkg-source -x bino_2.8-1+stereo3d7+lc1.dsc binary-source
cd binary-source
dpkg-buildpackage -B -us -uc
