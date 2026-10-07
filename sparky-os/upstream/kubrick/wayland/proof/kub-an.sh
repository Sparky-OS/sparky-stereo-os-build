#!/bin/bash
# analysis of a kub-proof run set: kub-an.sh <prefix>
cd /K3D/temp/kdesci-wl; p=$1
for c in sw-s5-1:5 sw-s5-2:5 sw-s5-3:5 sw-s10:10 sw-s2:2 gpu-s5-1:5 gpu-s5-2:5; do n=${c%%:*}; s=${c##*:}
  echo "== $n ($(sed -n 1,2p ev/$p-$n/capture.txt | tr '\n' ' '))"
  # widget origin: first GL row / col from the window picture
  OX=3 OY=$(python3 - <<PY
from PIL import Image; import numpy as np
im=np.array(Image.open('ev/$p-$n/window.png').convert('RGB')).astype(int); c=im[:,10]
ys=[y for y in range(40,len(c)) if abs(c[y]-239).max()>30 and abs(c[y-1]-239).max()<=30 and c[y].std()<60]
print(max(y for y in ys if y<120) if ys else 79)
PY
) DY0=1 python3 an-kub.py ev/$p-$n $s | sed -n 1,3p\;4,12p
done
