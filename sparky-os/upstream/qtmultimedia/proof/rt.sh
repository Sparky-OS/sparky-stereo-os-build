#!/bin/bash
# usage: [DEV=1] [IMG=qtmm-run:1] rt.sh <name> <steps-json> <qml args...>  : DEV=1 runs with the dev build of Qt Multimedia
W=/K3D/temp/qtmm-lane
P=/K3D/temp/partners/queue/players-stereo/.scratch/run
name=$1; steps=$2; shift 2
rm -rf $W/out/$name
DEVENV=""
if [ -n "$DEV" ]; then DEVENV="-e LD_LIBRARY_PATH=${DEVDIR:-/w/dev}/lib/x86_64-linux-gnu -e QML_IMPORT_PATH=${DEVDIR:-/w/dev}/lib/x86_64-linux-gnu/qt6/qml:/w/dragon-prefix/lib/x86_64-linux-gnu/qml:/w/dragon-prefix/lib/qml -e QT_PLUGIN_PATH=${DEVDIR:-/w/dev}/lib/x86_64-linux-gnu/qt6/plugins"; fi
exec docker run --rm --name qtmm-$name --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 \
  -e HOME=/tmp/home -e LIBGL_ALWAYS_SOFTWARE=${SW:-0} -e SCREEN -e PEXTRA -e QMLBIN -e APPCMD -e QMLFILE -e DEBIAN_FRONTEND=noninteractive $DEVENV \
  -v $P/passwd:/etc/passwd:ro -v $W:/w -v $P:/p:ro ${IMG:-qtmm-run:3} \
  dbus-run-session -- python3 /w/run/td.py /w/out/$name "$steps" "$@"
