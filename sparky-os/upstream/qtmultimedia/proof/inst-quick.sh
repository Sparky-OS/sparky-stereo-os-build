#!/bin/bash
# the follow-up proofs from the packages installed from the repository (fresh container, no development build)
cd /K3D/temp/qtmm-lane/run
export IMG=qtmm-fresh:1
unset DEV DEVDIR
Q="docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/qtmm-lane:/w qtmm-run:3"
{
echo "== shape fallback (edition defaults, installed packages): capture width 2560 = stereo"
for c in L-plain-sbs-32x9.mp4 L-plain-sbs-full.mp4 2d-239.mp4 2d-169.mp4 L-2d.mp4; do
  for app in dragon app; do
    n=ishp-$app-$c
    if [ $app = dragon ]; then APPCMD=/usr/bin/dragon ./rt.sh $n '[["wait",14],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
    else ./rt.sh $n '[["wait",12],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1; fi
    W=$($Q python3 -c "from PIL import Image; print(Image.open('/w/out/$n/c1.png').size[0])")
    echo "$app $c: capture width $W ($([ $W = 2560 ] && echo stereo || echo mono)), declarations=$(grep -c 'set_content(3)' ../out/$n/client0.log)"
  done
done
} > ../inst-shape.txt 2>&1
{
echo "== anamorphic 3D, installed packages: left eye of the capture against the test picture and ffmpeg's resizes of the stored eye (stereoScaling 0 bilinear, 1 bicubic, 2 Lanczos)"
for spec in "sar-sei-sbs-half.mp4 " "sar-mkv-sbs-half.mkv " "sar-sei-tb-half.mp4 tb-"; do
  set -- $spec; c=$1; pre=$2
  for S in 0 1 2; do
    n=isar-$c-$S
    ./rt.sh $n '[["wait",8],["cap","c1"]]' /w/clips/$c 0 0 - $S - >/dev/null 2>&1
    echo "$c stereoScaling=$S: $($Q python3 /w/run/psnr.py /w/out/$n/c1.png $pre | sed 's/  vs //' | tr '\n' ';')"
  done
done
echo
echo "== 2D control, anamorphic 2D clip (SAR 2:1, no stereo mark): Debian's Qt Multimedia against ours"
nice ffmpeg -v error -y -f lavfi -i "testsrc2=s=960x720:r=25:d=6" -vf "select=eq(n\,0),loop=-1:1:0,fps=25,trim=duration=6,setsar=2/1" -c:v libx264 -qp 0 -pix_fmt yuv420p ../clips/static-sar2d.mp4
for c in static-sar2d.mp4 static2d.mp4 static2d10.mkv; do
  IMG=qtmm-run:deb QMLFILE=/w/run/plain.qml ./rt.sh isar-deb-$c '[["wait",8],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  QMLFILE=/w/run/plain.qml ./rt.sh isar-our-$c '[["wait",8],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  echo "plain.qml $c: $($Q python3 /w/run/cmp.py /w/out/isar-deb-$c/c1.png /w/out/isar-our-$c/c1.png)"
done
IMG=qtmm-run:deb QMLFILE=/w/run/plain.qml ./rt.sh isar-deb2 '[["wait",8],["cap","c1"]]' /w/clips/static-sar2d.mp4 >/dev/null 2>&1
echo "noise floor, Debian against Debian: $($Q python3 /w/run/cmp.py /w/out/isar-deb-static-sar2d.mp4/c1.png /w/out/isar-deb2/c1.png)"
} > ../inst-sar.txt 2>&1
{
echo "== mastering luminance in the layer's colour description (installed packages): x265 --master-display L(10000000,1) = 1000 cd/m2, PQ"
PEXTRA='{"QT_LOGGING_RULES":"qt.multimedia.video.stereolayer.debug=true"}' ./rt.sh ipq '[["wait",12],["cap","c1"]]' /w/clips/ramp10-pq-md-sbs.mkv >/dev/null 2>&1
grep -h "set_mastering_luminance\|set_tf_named\|set_primaries_named\|set_image_description\|color description" ../out/ipq/client0.log ../out/ipq/client0.out | sed 's/^.*-> //'
} > ../inst-pq.txt 2>&1
echo done > ../inst-quick-done
