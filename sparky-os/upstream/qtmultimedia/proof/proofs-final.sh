#!/bin/bash
# the proofs that need the built trees: upscale, 2D control, depth, audio. usage: proofs-final.sh (after trees-done2)
cd /K3D/temp/qtmm-lane/run
Q="docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/qtmm-lane:/w qtmm-run:3"
{
echo "== upscale (half side by side, SEI, 1280x720: each eye 640x720 restored to 1280x720; capture at 1:1; the eye of the capture against references)"
for S in 0 1 2; do
  DEV=1 DEVDIR=/w/b-final ./rt.sh up$S '[["wait",5],["cap","c1"]]' /w/clips/up-sei-sbs-half.mp4 0 0 0 $S 0 >/dev/null 2>&1
  echo "stereoScaling=$S (0 bilinear, 1 bicubic, 2 Lanczos)"; $Q python3 /w/run/psnr.py /w/out/up$S/c1.png
done
} > ../proof-upscale.txt 2>&1
{
echo "== 2D control: a non-stereo video, Debian's Qt Multimedia 6.11.2-3 against ours (final build), same window, same frame"
for c in static2d.mp4 static2d10.mkv; do
  IMG=qtmm-run:deb QMLFILE=/w/run/plain.qml ./rt.sh c2d-deb-$c '[["wait",5],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  DEV=1 DEVDIR=/w/b-final QMLFILE=/w/run/plain.qml ./rt.sh c2d-our-$c '[["wait",5],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  echo "plain.qml, $c: $($Q python3 /w/run/cmp.py /w/out/c2d-deb-$c/c1.png /w/out/c2d-our-$c/c1.png)"
done
} > ../proof-2dcontrol.txt 2>&1
echo done > ../proofs-final-done
