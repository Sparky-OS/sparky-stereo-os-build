#!/bin/bash
# usage: matrix.sh <tag> <image> ; the alpha cases against one Qt. Evidence in $EVROOT/<tag>-<case>.
cd "$(dirname "$0")"
tag=$1; export IMG=$2 EVROOT=${EVROOT:-$PWD/../evidence}; mkdir -p $EVROOT
r() { n=$1; shift; echo "== $tag-$n"; timeout 200 bash drun.sh $tag-$n "$@" >/dev/null 2>&1; echo "rc=$?"; grep -E "EGLSHIM eglCreate|requested|window  " $EVROOT/$tag-$n/app.log; }
for f in 16 10 none; do
  CLIENT_ENV="QT_ALPHA_FMT=$f" WAIT=6 r gpu-$f bash /rig/client-alpha.sh
  CLIENT_ENV="QT_ALPHA_FMT=$f" NODECO=1 CSD=1 WAIT=6 r gpu-csd-$f bash /rig/client-alpha.sh
done
CLIENT_ENV="QT_ALPHA_FMT=16 QT_ALPHA_GL=0" WAIT=6 r raster-16 bash /rig/client-alpha.sh
CLIENT_ENV="QT_ALPHA_FMT=16 QT_ALPHA_OPAQUE=1" WAIT=6 r opaque-16 bash /rig/client-alpha.sh
CLIENT_ENV="QT_ALPHA_FMT=none QT_ALPHA_OPAQUE=1" WAIT=6 r opaque-none bash /rig/client-alpha.sh
echo MATRIX_DONE
