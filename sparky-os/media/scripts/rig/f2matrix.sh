#!/bin/bash
# usage: f2matrix.sh <prefix> <image> [MPVBIN]  -> results-<prefix>.txt : the placement of each eye's picture in its view
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/media-on-dmo/work/rig
pre=$1; img=$2; export MPVBIN=${3:-mpv}
: > results-$pre.txt
# case: name|screen|fullscreen(1/0)|geometry|clip|extra args
cases=(
"fs1024-unscaled|1024x640|1|--fullscreen|f2-sbs-600x200.mkv|--video-unscaled=yes"
"fs1024-fit|1024x640|1|--fullscreen|f2-sbs-600x200.mkv|"
"win960x540-sbs600x200|1280x800|0|--geometry=960x540|f2-sbs-600x200.mkv|"
"win700x500-sbs600x200|1280x800|0|--geometry=700x500|f2-sbs-600x200.mkv|"
"win800x800-half1280x720|1280x800|0|--geometry=800x800|f2-sbs-1280x720.mkv|"
"win1100x300-full1920x540|1280x800|0|--geometry=1100x300|f2-sbs-1920x540.mkv|"
"fs1280x800-tb400x600|1280x800|1|--fullscreen|f2-tb-400x600.mkv|"
"win500x700-tb400x600|1280x800|0|--geometry=500x700|f2-tb-400x600.mkv|"
)
vos=("dmabuf-wayland|dmabuf" "gpu-next|gn" "gpu|gpu" "gpu-next --gpu-api=opengl --gpu-context=wayland|gn-egl" "gpu --gpu-api=opengl --gpu-context=wayland|gpu-egl")
for c in "${cases[@]}"; do IFS='|' read -r name screen full geom clip extra <<< "$c"
 for v in "${vos[@]}"; do IFS='|' read -r vospec tag <<< "$v"; vo=${vospec%% *}; vextra=${vospec#"$vo"}; vextra=${vextra# }
  nm=$pre-$name-$tag
  FULL=$full SCREEN=$screen GEOM=$geom TAILN=0 scripts/run.sh $nm $img $vo clips/$clip '[3,4]' --background-color=#00AAAA $extra $vextra > /dev/null 2>&1
 done; done
python3 scripts/f2judge.py $pre
