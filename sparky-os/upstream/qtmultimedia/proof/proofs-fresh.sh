#!/bin/bash
# the measurements from the packages installed from the repository in a fresh container (qtmm-fresh:1)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/qtmm-lane/run
export IMG=qtmm-fresh:1
unset DEV DEVDIR
Q="docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v ${SPARKY_SCRATCH:?}/qtmm-lane:/w qtmm-run:3"
LOG='{"QT_LOGGING_RULES":"qt.multimedia.video.stereopresenter.debug=true;qt.multimedia.video.stereolayer.debug=true"}'
{
echo "== depth: the layer's buffer under the edition's defaults (stereoSurface BySource); levels of red per view, counted in the buffer before it is committed (KWin's capture is 8 bit)"
for c in ramp8-sbs.mkv ramp10-sbs.mkv ramp12-sbs.mkv ramp16-sbs.mkv ramp10-444-sbs.mkv ramp10-pq-md-sbs.mkv ramp10-hlg-sbs.mkv; do
  n=fr-dp-$c
  PEXTRA=$LOG ./rt.sh $n '[["wait",12],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  echo "$c: $(grep -h 'levels of red' ../out/$n/client0.out ../out/$n/client0.log | head -1 | sed 's/.*packing/packing/; s/ right first.*view/ view/; s/QVideoFrameFormat:://')"
  grep -h "color description\|does not take" ../out/$n/client0.log ../out/$n/client0.out | head -1 | sed 's/^/    /'
  echo "    layer buffer: $(grep -o 'create_buffer(new id wl_buffer#[0-9]*, 0, [0-9]*, [0-9]*, [0-9]*, [0-9]*)' ../out/$n/client0.log | grep -v '64, 64, 256' | head -1 | sed 's/.*#[0-9]*, 0, //')   capture: $($Q python3 -c "from PIL import Image; print(Image.open('/w/out/$n/c1.png').size)")"
done
echo "(shm format codes: 1 XRGB8888, 808669784 XRGB2101010 'XR30', 942948952 XBGR16161616 'XB48'; a buffer is both views: 2560 wide = two views of 1280)"
echo
echo "== chroma: a one pixel red and blue pattern; the share of pixels that are pure red or blue in the left eye of the capture (1:1)"
for spec in "chromaH-444p10-sbs.mkv H" "chromaH-444p8-sbs.mkv H" "chromaH-422p10-sbs.mkv H" "chromaH-420p10-sbs.mkv H" "chromaV-444p10-sbs.mkv V" "chromaV-444p8-sbs.mkv V" "chromaV-422p10-sbs.mkv V" "chromaV-420p10-sbs.mkv V"; do
  set -- $spec; n=fr-ch-$1
  ./rt.sh $n '[["wait",10],["cap","c1"]]' /w/clips/$1 >/dev/null 2>&1
  echo "$1 ($2 pattern): $($Q python3 /w/run/chroma2.py $2 /w/out/$n/c1.png | sed 's/^[^:]*: //')"
done
} > ../fresh-depth-chroma.txt 2>&1
{
echo "== upscale (half side by side, SEI, 1280x720, no sample aspect ratio: each eye 640x720 restored to 1280x720; capture at 1:1)"
for S in 0 1 2; do
  ./rt.sh fr-up$S '[["wait",8],["cap","c1"]]' /w/clips/up-sei-sbs-half.mp4 0 0 - $S - >/dev/null 2>&1
  echo "stereoScaling=$S (0 bilinear, 1 bicubic, 2 Lanczos)"; $Q python3 /w/run/psnr.py /w/out/fr-up$S/c1.png
done
echo
echo "== 2D control: a non-stereo video, Debian's Qt Multimedia 6.11.2-3 against ours (installed packages), same window and frame"
for c in static2d.mp4 static2d10.mkv; do
  IMG=qtmm-run:deb QMLFILE=/w/run/plain.qml ./rt.sh fr-c2d-deb-$c '[["wait",8],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  QMLFILE=/w/run/plain.qml ./rt.sh fr-c2d-our-$c '[["wait",8],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  echo "plain.qml, $c: $($Q python3 /w/run/cmp.py /w/out/fr-c2d-deb-$c/c1.png /w/out/fr-c2d-our-$c/c1.png)"
done
IMG=qtmm-run:deb QMLFILE=/w/run/plain.qml ./rt.sh fr-c2d-deb2 '[["wait",8],["cap","c1"]]' /w/clips/static2d.mp4 >/dev/null 2>&1
echo "noise floor, Debian against Debian: $($Q python3 /w/run/cmp.py /w/out/fr-c2d-deb-static2d.mp4/c1.png /w/out/fr-c2d-deb2/c1.png)"
} > ../fresh-upscale-2d.txt 2>&1
{
echo "== audio from the installed packages (edition defaults); a null sink of 48 kHz S32 in a PipeWire of its own"
for c in a44k16.mkv a96k24.mkv a44kaac.mp4; do
  ./ra.sh fr-au-$c $c > ../out/fr-au-$c.txt 2>&1
  echo "$c (stream: $(ffprobe -v error -select_streams a -show_entries stream=sample_fmt,sample_rate,channels -of csv=p=0 ../clips/$c))"
  grep "Stream" ../out/fr-au-$c.txt | sed 's/^node Qml Runtime class=Stream\/Output\/Audio app=None -> /   PipeWire stream /'
  grep -h "audio sink format\|audio resampler" ../out/fr-au-$c/app.out | sed 's/^qt.multimedia.ffmpeg.utils: /   /' | cut -c1-330
done
} > ../fresh-audio.txt 2>&1
echo done > ../proofs-fresh-done
