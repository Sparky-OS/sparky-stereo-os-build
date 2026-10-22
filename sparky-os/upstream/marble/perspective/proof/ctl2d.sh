#!/bin/bash
# (f) stereo off: Debian's marble against the patched marble, whole-screen pixel difference; flavour of the patched one: $1 (patched|pkg)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/marble-lane/work; F=${1:-patched}; T=${2:-ctl}
for proj in 0 7; do
  ./app-run.sh $T-stock-$proj stock marble PROJ=$proj >/dev/null 2>&1
  ./app-run.sh $T-$F-$proj $F marble PROJ=$proj >/dev/null 2>&1
  python3 - <<P
from PIL import Image; import numpy as np
a=np.array(Image.open('out/$T-stock-$proj/c1.png').convert('RGBA')); b=np.array(Image.open('out/$T-$F-$proj/c1.png').convert('RGBA'))
print('projection $proj: shape',a.shape,b.shape,'differing pixels:',int(np.any(a!=b,axis=2).sum()) if a.shape==b.shape else 'shape differs')
a2=np.array(Image.open('out/$T-stock-$proj/c2.png').convert('RGBA')); print('   (stock c1 vs c2 of the same run, stability): ',int(np.any(a!=a2,axis=2).sum()))
P
done
