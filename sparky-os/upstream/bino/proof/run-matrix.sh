#!/bin/bash
# flat stereo matrix: usage run-matrix.sh <prefix>   (GPU client with the glFinish shim unless SOFT=1)
cd "$(dirname "$0")"
pre=${1:-m}
[ -n "$SOFT" ] && export LIBGL_ALWAYS_SOFTWARE=1 || export BINO_ENV="LD_PRELOAD=/o/finish-shim.so"
export WAIT=${WAIT:-10}
run() { n=$1; shift; ./drun.sh $pre-$n -- --stereo -o stereo -l one "$@" >/dev/null 2>&1; echo "$n: $(grep -h -E 'meta data from ffprobe|input mode for' ../evidence/$pre-$n/bino.log | sed 's/Bino: //' | tr '\n' ';')"; }
# detection (no -i given)
run tag-sbsL /clips/sbs-L-tag.mkv
run tag-sbsR /clips/sbs-R-tag.mkv
run tag-tbL  /clips/tb-L-tag.mkv
run tag-tbR  /clips/tb-R-tag.mkv
run sei-sbsL /clips/sei-sbs-L.mp4
run sei-tbL  /clips/sei-tb-L.mp4
run raw-sbsL /clips/sbs-L.mkv
run raw-tbL  /clips/tb-L.mkv
# told explicitly
run told-sbsL -i left-right /clips/sbs-L.mkv
run told-sbsR -i right-left /clips/sbs-R.mkv
run told-tbL  -i top-bottom /clips/tb-L.mkv
run told-tbR  -i bottom-top /clips/tb-R.mkv
python3 analyze.py ../evidence/$pre-*
