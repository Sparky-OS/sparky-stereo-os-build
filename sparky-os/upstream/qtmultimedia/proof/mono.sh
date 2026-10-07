#!/bin/bash
# one view only (no layer: the offerable build): the colour of the one view per clip and view
W=/K3D/temp/qtmm-lane
for spec in "Z-sei-sbs-L.mp4 0" "Z-sei-sbs-R.mp4 0" "Z-sei-tb-L.mp4 0" "Z-mkv-tb-R.mkv 0" "Z-sei-rows.mp4 0" "Z-sei-cols.mp4 0" "Z-sei-checker.mp4 0" "Zn-mkv-seq-L.mkv 0" "Zn-mkv-seq-R.mkv 0" "Z-sei-seq.mp4 0" "Z-plain-seq.mp4 11"; do
  set -- $spec
  for v in 0 1 2; do
    n=mono-$1-$v
    DEV=1 DEVDIR=/w/b-offer $W/run/rt.sh $n '[["wait",6],["cap","c1"]]' /w/clips/$1 $2 0 $v >/dev/null 2>&1
    docker run --rm --platform linux/amd64 -v $W:/w qtmm-run:3 python3 -c "
from PIL import Image; import numpy as np
a=np.array(Image.open('/w/out/$n/c1.png').convert('RGB'))
print('$1 view=$v (0 both, 1 left, 2 right): size', a.shape[1], 'centre', tuple(int(x) for x in a[400,640 if a.shape[1]==1280 else 640]))"
  done
done
