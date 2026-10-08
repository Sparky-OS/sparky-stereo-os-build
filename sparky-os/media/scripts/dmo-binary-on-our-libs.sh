#!/bin/sh
# dmo's own, unpatched ffmpeg binary (extracted from its package), run against the libraries of THIS image
B=/dmobin/usr/bin
echo "libraries it loads: $(ldd $B/ffmpeg | awk '/libavcodec|libavutil|libavformat/{print $3}' | tr '\n' ' ')"
for l in libavcodec63 libavformat63; do printf "  %s: %s\n" $l "$(dpkg -l $l | awk '/^ii/{print $3}')"; done
for c in ord-sbs-L-g12.mp4 ord-sbs-R-g250.mkv cat-3d2d.mp4 hevc-sbs-L-g12.mp4; do
  n=$($B/ffmpeg -nostats -v info -threads 4 -i /clips/$c -an -vf showinfo -f null - 2>&1 | grep -c "side data - Stereo 3D"); t=$($B/ffmpeg -nostats -v info -threads 4 -i /clips/$c -an -vf showinfo -f null - 2>&1 | grep -c "\] n: ")
  echo "dmo's ffmpeg binary, $c: $n of $t frames with Stereo 3D"
done
