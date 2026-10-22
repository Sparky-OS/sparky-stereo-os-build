#!/bin/bash
# usage: matrix.sh <prefix> <image> <vo> [MPVBIN]   -> runs/<prefix>-*, results in results-<prefix>.txt
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/media-on-dmo/work/rig
pre=$1; img=$2; vo=$3
dense='[0.8,1.2,1.6,2.0,2.4,2.8,3.2,3.6,4.0,4.4,4.8,5.2,5.6,6.0,6.5,7.5]'
slow='[1.2,2.0,2.8,3.6,4.4,5.2,6.0,7.0]'
list=""
for kind in sbs tb; do for e in L R; do for g in 12 250; do for x in mp4 mkv; do list="$list ord-$kind-$e-g$g.$x:3d:$slow"; done; done; done; done
for c in hevc-sbs-L-g12.mp4 hevc-sbs-L-g250.mkv hevc-sbs-R-g250.mkv hevc-tb-L-g12.mp4 hevc-tb-L-g250.mp4 hevc-tb-R-g12.mkv; do list="$list $c:3d:$slow"; done
list="$list hevc-2d.mp4:2d:$slow hevc-cat-3d2d.mp4:3d>2d@75:x"
list="$list sei-every-sbs-L.mp4:3d:$slow sei-every-tb-R.mp4:3d:$slow mkvmode-sbs-L.mkv:3d:$slow mkvmode-tb-R.mkv:3d:$slow"
for c in x265-sbs-L-g12.mp4 x265-sbs-L-g250.mkv x265-tb-L-g12.mkv x265-tb-L-g250.mp4; do list="$list $c:3d:$slow"; done
list="$list x265-cat-3d2d.mp4:3d>2d@75:x"
list="$list ord-2d.mp4:2d:$slow x264-sbs-L-g12.mp4:3d:$slow cat-3d2d.mp4:3d>2d@75:$dense cat-3d2d.mkv:3d>2d@75:$dense cat-2d3d.mp4:2d>3d@75:$dense cat-sbs-tb.mp4:3d>3d@75:$dense cancel-60.mp4:3d>2d@60:$dense"
: > results-$pre.txt
run1() { spec=$1; clip=${spec%%:*}; r=${spec#*:}; exp=${r%%:*}; t=${r#*:}; nm=$pre-${clip%.*}-${clip##*.}
  if [[ $exp == *'>'* ]]; then n=${exp#*@}
    STEPS=$(python3 scripts/stepsfor.py $((n-6)) 12) MPVBIN=${MPVBIN:-mpv} TAILN=0 scripts/run.sh $nm $img $vo clips/$clip '[1]' --pause --input-ipc-server=/tmp/mpv.sock $EXTRA > /dev/null 2>&1
    python3 scripts/judge_step.py runs/$nm $exp >> results-$pre.txt 2>&1 || true
  else
    MPVBIN=${MPVBIN:-mpv} TAILN=0 scripts/run.sh $nm $img $vo clips/$clip "$t" $EXTRA > /dev/null 2>&1
    python3 scripts/judge.py runs/$nm $exp >> results-$pre.txt 2>&1 || true
  fi; }
export -f run1; export pre img vo MPVBIN EXTRA
echo $list | tr ' ' '\n' | grep -E "${ONLY:-.}" | xargs -P ${JOBS:-3} -I{} bash -c 'run1 "$1"' _ {}
sort -o results-$pre.txt results-$pre.txt; grep -c PASS results-$pre.txt; grep -c FAIL results-$pre.txt
