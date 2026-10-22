#!/bin/bash
# PSNR of the left eye (restored view) against ffmpeg's references and the truth, for anamorphic 3D clips; scaling 0 bilinear 1 bicubic 2 Lanczos
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/qtmm-lane/run
Q="docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v ${SPARKY_SCRATCH:?}/qtmm-lane:/w qtmm-run:3"
for build in before offer after; do
  case $build in
    before) env=(); view="-";;
    offer) env=(DEV=1 DEVDIR=/w/b-luma); view=1;;
    after) env=(DEV=1 DEVDIR=/w/b-final); view="-";;
  esac
  for spec in "sar-sei-sbs-half.mp4 " "sar-mkv-sbs-half.mkv " "sar-sei-tb-half.mp4 tb-"; do
    set -- $spec; c=$1; pre=$2
    for S in 0 1 2; do
      n=sar-$build-$c-$S
      env "${env[@]}" ./rt.sh $n '[["wait",5],["cap","c1"]]' /w/clips/$c 0 0 $view $S - >/dev/null 2>&1
      echo "$build $c stereoScaling=$S: $($Q python3 /w/run/psnr.py /w/out/$n/c1.png $pre | sed 's/  vs //' | tr '\n' ';')"
    done
  done
done
