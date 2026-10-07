#!/bin/bash
# usage: IMG=plank-run:B [PBIN=...] all.sh <prefix>: the whole proof, one run after the other, results in out/<prefix>-*.txt
W=/K3D/temp/partners/queue/plank-player
p=$1
$W/run/matrix.sh $p plain sei-sbs-L.mp4 sei-sbs-R.mp4 sei-tb-L.mp4 sei-tb-R.mp4 mkv-sbs-L.mkv mkv-sbs-R.mkv mkv-tb-L.mkv mkv-tb-R.mkv kf-sei-sbs-L.mp4 2d.mp4 plain-sbs-32x9.mp4 plain-sbs-full.mp4 plain-sbs-half.mp4 plain-tb-half.mp4 > $W/out/$p-plain.txt 2>&1
$W/run/matrix.sh $p osd sei-sbs-L.mp4 sei-tb-R.mp4 mkv-sbs-R.mkv kf-sei-sbs-L.mp4 2d.mp4 plain-sbs-32x9.mp4 > $W/out/$p-osd.txt 2>&1
{
$W/run/manual.sh $p sbs-half L-plain-sbs-half.mp4 5
$W/run/manual.sh $p sbs-half-R-swap L-plain-sbs-half-R.mp4 5 11
$W/run/manual.sh $p tb-half L-plain-tb-half.mp4 7
$W/run/manual.sh $p tb-full L-plain-tb-full.mp4 8
$W/run/manual.sh $p sbs-full L-plain-sbs-full.mp4 6
$W/run/manual.sh $p 32x9-not3d L-plain-sbs-32x9.mp4 15
$W/run/manual.sh $p sei-swap L-sei-sbs-L.mp4 16
$W/run/manual.sh $p sei-not3d L-sei-sbs-L.mp4 15
$W/run/manual.sh $p sei-left L-sei-sbs-L.mp4 1
} > $W/out/$p-manual.txt 2>&1
echo done > $W/out/$p-done
