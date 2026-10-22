#!/bin/sh
# Reproduces the two FFmpeg 9.0.2 findings of the ArtCraft lane (2026-10-08) in docker, with deb-multimedia's FFmpeg and ours
# (media-on-dmo lane). Needs: docker, the images mdmo-ff:dmo (deb-multimedia's ffmpeg 10:9.0.2-dmo1 on debian:testing) and
# mdmo-ff:ours (ours, +stereo3d2, with python3), the lane's fixtures (${SPARKY_WORKSPACES}/artcraft-stereo/work/fixtures/video),
# mkvtoolnix on the host (mkvpropedit, to make the display-size variants), python3 on the host (boxes.py).
# 1. vexu beside st3d: remux.sh remuxes every Matroska fixture to MP4 (-c copy, default strictness and -strict unofficial) and
#    reads the result back; probe.sh reads the four probe files (the same MP4 with vexu or st3d hidden, and the boxes swapped).
# 2. the pixel aspect: sar.sh prints the SAR FFmpeg reads for the display-size variants (sar-files/) and the pasp the MP4 gets.
# Both builds give byte-identical remuxes and identical reads: the behaviour is libavformat's (mov.c, movenc.c, matroskadec.c),
# which our patches do not touch.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -eu
H=$(cd "$(dirname "$0")" && pwd)/..
FX=${FX:-${SPARKY_WORKSPACES:?}/artcraft-stereo/work/fixtures/video}
for t in dmo ours; do
  echo "=== $t"
  mkdir -p "$H/out-$t"
  docker run --rm --platform linux/amd64 --cpus 1 --user "$(id -u):$(id -g)" -v "$FX":/fx:ro -v "$H/repro":/r:ro -v "$H/out-$t":/out "mdmo-ff:$t" sh -c 'cp /r/*.py /r/*.sh /out/ 2>/dev/null; /out/remux.sh r'
  docker run --rm --platform linux/amd64 --cpus 1 --user "$(id -u):$(id -g)" -v "$H/probe-files":/out:ro "mdmo-ff:$t" sh -c 'for f in probe-original probe-no-vexu probe-no-st3d probe-vexu-first; do printf "%-20s " $f; ffprobe -hide_banner /out/$f.mp4 2>&1 | grep -E "Stereo 3D|nvalid" | sed "s/^ *//" | tr "\n" "|"; echo; done'
done
python3 "$H/repro/boxes.py" "$H"/out-ours/r/*.u.mp4 | head -60
