#!/bin/bash
cd /K3D/temp/qtmm-lane/run
Q="docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/qtmm-lane:/w qtmm-run:3"
for build in edition offerable; do
  [ $build = edition ] && D=/w/b-final || D=/w/b-luma
  for c in L-plain-sbs-32x9.mp4 L-plain-sbs-full.mp4 2d-239.mp4 2d-169.mp4 L-2d.mp4; do
    for app in dragon app; do
      n=shp-$build-$app-$c
      if [ $app = dragon ]; then
        APPCMD=/usr/bin/dragon DEV=1 DEVDIR=$D ./rt.sh $n '[["wait",14],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
      else
        DEV=1 DEVDIR=$D ./rt.sh $n '[["wait",12],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
      fi
      W=$($Q python3 -c "from PIL import Image; print(Image.open('/w/out/$n/c1.png').size[0])")
      echo "$build $app $c: capture width $W ($([ $W = 2560 ] && echo stereo || echo mono)), declarations=$(grep -c 'set_content(3)' ../out/$n/client0.log)"
    done
  done
done
