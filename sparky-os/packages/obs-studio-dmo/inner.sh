#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Inside the builder: deb-multimedia's source, our patches, our provenance, Lean Code, the build.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
UPSTREAM=1:33.0.1-dmo2
VERSION=$UPSTREAM+stereo3d2
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:?the host passes the date of the recipe: build-provenance.sh}
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Ramos (Capitain Jack)"
WORK=$(mktemp -d "$OUT/.obs.XXXXXX")
cp /src/obs-studio-dmo_33.0.1.orig.tar.xz /src/obs-studio-dmo_33.0.1.orig-obs-websocket-5-7-6.tar.xz "$WORK/"
cd "$WORK"
dpkg-source -x /src/obs-studio-dmo_33.0.1-dmo2.dsc source > dpkg-source.log
cd source
for p in "$HERE"/patches/*.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
# patch 0001 adds three exported functions to libobs and patch 0008 four more, so a program linked against them needs
# this build: the shlibs minimum moves to it (Debian Policy 8.6, shared library ABI changes); the other packages keep
# dh_makeshlibs as it was
printf '\noverride_dh_makeshlibs:\n\tdh_makeshlibs -plibobs0t64 -V"libobs0t64 (>= %s~)"\n\tdh_makeshlibs -Nlibobs0t64\n' \
	"$VERSION" >> debian/rules
python3 - "$VERSION" <<'PY'
import os, re, sys
version = sys.argv[1]
# debian/control stays as deb-multimedia ships it, with one build dependency more: patch 0011 links media playback
# with the stereo layer's libstereo-av (pkg-config stereo-av). The build's provenance step (repo/provenance.sh --tree,
# run by Lean Code's dh_builddeb) stamps the binaries with our Maintainer and keeps Christian Marillat as
# Original-Maintainer
control = open('debian/control').read()
control, n = re.subn(r'^(Build-Depends:[^\n]*\n(?:[ \t][^\n]*\n)*?[ \t][^\n]*libavdevice-dev,)',
                     r'\1 libstereo-av-dev (>= 1.23.0),', control, count=1, flags=re.M)
if n != 1:
    sys.exit('debian/control: no libavdevice-dev in Build-Depends to put libstereo-av-dev beside')
open('debian/control', 'w').write(control)
entry = f"""obs-studio-dmo ({version}) unstable; urgency=medium

  * Sparky Stereo OS (ORDER 61, milestone 3): a side by side canvas is drawn
    once per eye, in one eye's space; OBS's preview, studio mode's views and
    the projectors can be declared 3D areas (patches 0008 and 0009); Render
    Delay keeps each eye's frames apart (0010); media playback hands on a
    stream's own stereo mark and pairs frames in turn and the two views of an
    MV-HEVC stream through the stereo layer's libstereo-av (0011, which adds
    libstereo-av-dev to Build-Depends).
  * A hotkey triggered by name through obs-websocket runs on the UI thread, as
    a key press does (0012); the custom FFmpeg output's raw callbacks and its
    stop share a lock on the encoder's data (0013, the race upstream's issue
    14153 sees from its other side).
  * libobs exports four new functions (obs_get_video_eye_size,
    obs_get_render_eye, obs_display_set_views, obs_display_get_views), so its
    shlibs name this version as the minimum.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {os.environ['SOURCE_DATE_RFC2822']}

obs-studio-dmo (1:33.0.1-dmo2+stereo3d1) unstable; urgency=medium

  * Sparky Stereo OS (ORDER 61, milestone 2): libobs carries the main canvas's
    stereo layout, and while they work x264, VA-API (through the edition's
    FFmpeg), NVENC, the muxer helper (Matroska StereoMode, MP4 st3d), the
    hybrid MP4 muxer and the custom FFmpeg output write the 3D marks from it.
    Nothing changes on a 2D canvas.
  * libobs exports three new functions (obs_set_video_stereo3d,
    obs_get_video_stereo3d, obs_encoder_get_stereo3d), so its shlibs name
    this version as the minimum.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Sat, 21 Nov 2026 01:51:21 +0000

"""
open('debian/changelog', 'w').write(entry + open('debian/changelog').read())
PY
python3 "$TOOLKIT/repo/reproducible.py" normalize "$SOURCE_DATE_EPOCH" debian
PYTHONPATH="$TOOLKIT" python3 -m lean.debian_prepare . "$VERSION+lc1"
PYTHONPATH="$TOOLKIT" dpkg-buildpackage -us -uc -sa -j"${JOBS:-4}" > "$WORK/build.log" 2>&1 || { tail -60 "$WORK/build.log"; exit 1; }
cd "$WORK"
cp ./*.deb ./*.dsc ./*.debian.tar.xz ./*.orig*.tar.xz ./*.buildinfo ./*.changes ./*.json "$OUT/" 2>/dev/null || true
cp build.log "$OUT/build.log"
(cd "$OUT" && PYTHONPATH="$TOOLKIT" python3 -m lean.release check-debs ./*.deb)
