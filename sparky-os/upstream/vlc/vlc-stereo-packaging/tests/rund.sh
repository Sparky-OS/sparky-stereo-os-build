#!/bin/bash
cd /K3D/temp/partners/queue/vlc-stereo
export INST=1 IMG=${DIMG:-vlc-both:4} VBIN=/usr/bin/vlc-stereo HW=--avcodec-hw=any SW=0 PRE=8
for c in ${CLIPS:-x264-2d.mp4 x264-sbs.mp4 x264-sbs.mkv x264-tb.mp4 x264-tb.mkv}; do
  n=${TAG:-d1}-${c%%.*}-${c##*.}
  SCREEN=2000x1200 ./run/vlc-test.sh $n vlc-osd.sh $c -- $XARGS
  echo "== $n"; grep -v SUPP run/out/$n/props.txt | cut -c1-90
  echo "decoder: $(grep -o 'Using .* for hardware decoding' run/out/$n/vlc.log | head -n1 | cut -c1-60) vouts $(grep -c 'Opening vout display wrapper' run/out/$n/vlc.log)"
  docker run --rm --user $(id -u):$(id -g) -v $PWD:/w vlc-stereo-build:2 python3 /w/run/an-osd.py /w/run/out/$n/a.png /w/run/out/$n/b.png ${WIN:-360 240 1280 720} 2000
done
echo done > run/out/${TAG:-d1}.done
