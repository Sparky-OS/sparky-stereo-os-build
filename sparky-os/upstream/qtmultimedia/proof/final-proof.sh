#!/bin/bash
# the proofs from the packages installed from the repository in a fresh container (qtmm-fresh:1), no development build
cd /K3D/temp/qtmm-lane/run
export IMG=qtmm-fresh:1
unset DEV DEVDIR
P=fp
# 1. the QML test app (Qt Multimedia's VideoOutput on its own): the clip matrix, declared and undeclared
./mx.sh $P-app "Z-sei-sbs-L.mp4" "Z-sei-sbs-R.mp4" "Z-sei-tb-L.mp4" "Z-sei-tb-R.mp4" "Z-mkv-sbs-L.mkv" "Z-mkv-sbs-R.mkv" "Z-mkv-tb-L.mkv" "Z-mkv-tb-R.mkv" "L-kf-sei-sbs-L.mp4" "Z-hevc-sbs-L.mp4" "Z-sei-rows.mp4" "Z-sei-cols.mp4" "Z-sei-checker.mp4" "Z-sei-seq.mp4" "Z-mkv-rows-L.mkv" "Z-mkv-rows-R.mkv" "Z-mkv-cols-L.mkv" "Z-mkv-cols-R.mkv" "Z-mkv-checker-L.mkv" "Z-mkv-checker-R.mkv" "Zn-mkv-seq-L.mkv" "Zn-mkv-seq-R.mkv" "Z-mkv-anaglyph-cr.mkv" "L-2d.mp4" "L-plain-sbs-32x9.mp4 0 0 - - - 1" "L-plain-sbs-full.mp4 3" "L-plain-sbs-half.mp4 2" "L-plain-sbs-half-R.mp4 2 1" "L-plain-tb-half.mp4 5" "L-plain-tb-full.mp4 6" "Z-plain-rows.mp4 8" "Z-plain-cols.mp4 9" "Z-plain-checker.mp4 10" "Z-plain-seq.mp4 11" > ../fp-app.txt 2>&1
# 2. Dragon Player
APPCMD=/usr/bin/dragon WAIT=9 CROP_TOP=60 NO_BAR=1 ./mx.sh $P-dragon Z-sei-sbs-L.mp4 Z-sei-sbs-R.mp4 Z-sei-tb-L.mp4 Z-sei-tb-R.mp4 Z-mkv-sbs-L.mkv Z-mkv-sbs-R.mkv Z-mkv-tb-L.mkv Z-mkv-tb-R.mkv L-kf-sei-sbs-L.mp4 Z-hevc-sbs-L.mp4 Z-sei-rows.mp4 Z-sei-cols.mp4 Z-sei-checker.mp4 Z-sei-seq.mp4 Z-mkv-rows-L.mkv Z-mkv-cols-R.mkv Z-mkv-checker-L.mkv Zn-mkv-seq-L.mkv Zn-mkv-seq-R.mkv Z-mkv-anaglyph-cr.mkv L-plain-sbs-32x9.mp4 L-2d.mp4 > ../fp-dragon.txt 2>&1
# 3. Plank Player
export PLANKBIN=/usr/bin/plank-player
./pk.sh plain $P-pk sei-sbs-L.mp4 sei-sbs-R.mp4 sei-tb-L.mp4 sei-tb-R.mp4 mkv-sbs-L.mkv mkv-sbs-R.mkv mkv-tb-L.mkv mkv-tb-R.mkv kf-sei-sbs-L.mp4 2d.mp4 plain-sbs-32x9.mp4 plain-sbs-full.mp4 plain-sbs-half.mp4 plain-tb-half.mp4 > ../fp-plank-plain.txt 2>&1
./pk.sh osd $P-pk sei-sbs-L.mp4 sei-tb-R.mp4 mkv-sbs-R.mkv kf-sei-sbs-L.mp4 2d.mp4 plain-sbs-32x9.mp4 > ../fp-plank-osd.txt 2>&1
{
./pk.sh manual $P-pk sbs-half L-plain-sbs-half.mp4 5
./pk.sh manual $P-pk sbs-half-R-swap L-plain-sbs-half-R.mp4 5 11
./pk.sh manual $P-pk tb-half L-plain-tb-half.mp4 7
./pk.sh manual $P-pk tb-full L-plain-tb-full.mp4 8
./pk.sh manual $P-pk sbs-full L-plain-sbs-full.mp4 6
./pk.sh manual $P-pk 32x9-not3d L-plain-sbs-32x9.mp4 15
./pk.sh manual $P-pk sei-swap L-sei-sbs-L.mp4 16
./pk.sh manual $P-pk sei-not3d L-sei-sbs-L.mp4 15
./pk.sh manual $P-pk sei-left L-sei-sbs-L.mp4 1
} > ../fp-plank-manual.txt 2>&1
echo done > ../final-proof-done
