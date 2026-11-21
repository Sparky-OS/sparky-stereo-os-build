#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# Inside the builder: deb-multimedia's source, our patches, our provenance, Lean Code, the build.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
UPSTREAM=1:33.0.1-dmo2
VERSION=$UPSTREAM+stereo3d1
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
python3 - "$VERSION" <<'PY'
import os, sys
version = sys.argv[1]
# debian/control stays as deb-multimedia ships it: the build's provenance step (repo/provenance.sh --tree, run by Lean
# Code's dh_builddeb) stamps the binaries with our Maintainer and keeps Christian Marillat as Original-Maintainer
entry = f"""obs-studio-dmo ({version}) unstable; urgency=medium

  * Sparky Stereo OS (ORDER 61, milestone 2): libobs carries the main canvas's
    stereo layout, and while they work x264, VA-API (through the edition's
    FFmpeg), NVENC, the muxer helper (Matroska StereoMode, MP4 st3d), the
    hybrid MP4 muxer and the custom FFmpeg output write the 3D marks from it.
    Nothing changes on a 2D canvas.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  {os.environ['SOURCE_DATE_RFC2822']}

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
