#!/bin/bash
cd /K3D/temp/qtmm-lane/run
export DEV=1
./pk.sh plain pm1 sei-sbs-L.mp4 sei-sbs-R.mp4 sei-tb-L.mp4 sei-tb-R.mp4 mkv-sbs-L.mkv mkv-sbs-R.mkv mkv-tb-L.mkv mkv-tb-R.mkv kf-sei-sbs-L.mp4 2d.mp4 plain-sbs-32x9.mp4 plain-sbs-full.mp4 plain-sbs-half.mp4 plain-tb-half.mp4 > ../pm1-plain.txt 2>&1
./pk.sh osd pm1 sei-sbs-L.mp4 sei-tb-R.mp4 mkv-sbs-R.mkv kf-sei-sbs-L.mp4 2d.mp4 plain-sbs-32x9.mp4 > ../pm1-osd.txt 2>&1
{
./pk.sh manual pm1 sbs-half L-plain-sbs-half.mp4 5
./pk.sh manual pm1 sbs-half-R-swap L-plain-sbs-half-R.mp4 5 11
./pk.sh manual pm1 tb-half L-plain-tb-half.mp4 7
./pk.sh manual pm1 tb-full L-plain-tb-full.mp4 8
./pk.sh manual pm1 sbs-full L-plain-sbs-full.mp4 6
./pk.sh manual pm1 32x9-not3d L-plain-sbs-32x9.mp4 15
./pk.sh manual pm1 sei-swap L-sei-sbs-L.mp4 16
./pk.sh manual pm1 sei-not3d L-sei-sbs-L.mp4 15
./pk.sh manual pm1 sei-left L-sei-sbs-L.mp4 1
} > ../pm1-manual.txt 2>&1
echo done > ../pm1-done
