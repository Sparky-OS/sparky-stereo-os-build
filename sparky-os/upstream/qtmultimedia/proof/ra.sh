#!/bin/bash
# usage: [DEV=1 DEVDIR=/w/b-final] [SINKRATE= SINKFMT=] [PEXTRA=json] ra.sh <name> <clip file in clips/>
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
W=${SPARKY_SCRATCH:?}/qtmm-lane
P=${SPARKY_WORKSPACES:?}/players-stereo/.scratch/run
name=$1; clip=$2
rm -rf $W/out/$name
DEVENV=""
if [ -n "$DEV" ]; then DEVENV="-e LD_LIBRARY_PATH=${DEVDIR:-/w/dev}/lib/x86_64-linux-gnu -e QML_IMPORT_PATH=${DEVDIR:-/w/dev}/lib/x86_64-linux-gnu/qt6/qml -e QT_PLUGIN_PATH=${DEVDIR:-/w/dev}/lib/x86_64-linux-gnu/qt6/plugins"; fi
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 2 -e HOME=/tmp/homea -e SINKRATE -e SINKFMT -e PEXTRA $DEVENV -v $P/passwd:/etc/passwd:ro -v $W:/w ${IMG:-qtmm-run:4} dbus-run-session -- python3 /w/run/audio.py /w/out/$name /w/clips/$clip
