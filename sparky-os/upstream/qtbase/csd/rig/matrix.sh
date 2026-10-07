#!/bin/bash
# usage: matrix.sh <c|o> ; runs the proof cases for Debian's Qt (c) or ours (o)
cd "$(dirname "$0")/.."
export EVROOT=$PWD/evidence
p=$1
case $p in c) IMG=qtbase-proof:debian-in;; o) IMG=qtbase-proof:ours-in;; esac
export IMG
r() { n=$1; shift; echo "== $p-$n"; timeout 200 bash rig/drun.sh $p-$n "$@" >/dev/null 2>&1; echo "rc=$? $(tail -1 evidence/$p-$n/app.log 2>/dev/null)"; }
CSD="NODECO=1 CSD=1"
# qt-stereo-test: Qt's own decorations (KWin without a decoration plugin), GPU and software
env $CSD WAIT=6 bash -c "$(declare -f r); p=$p; r qt-csd-gpu bash /rig/client-qt.sh"
env $CSD SOFT=1 WAIT=6 bash -c "$(declare -f r); p=$p; r qt-csd-sw bash /rig/client-qt.sh"
# server-side decorations (Breeze), GPU
env WAIT=6 bash -c "$(declare -f r); p=$p; r qt-ssd-gpu bash /rig/client-qt.sh"
# 2D controls: stereo off GL widget, plain widgets window, with Qt's decorations, GPU and software
env $CSD QT_STEREO_OFF=1 WAIT=6 bash -c "$(declare -f r); p=$p; r off-csd-gpu bash /rig/client-qt.sh"
env $CSD QT_STEREO_OFF=1 SOFT=1 WAIT=6 bash -c "$(declare -f r); p=$p; r off-csd-sw bash /rig/client-qt.sh"
env $CSD WAIT=6 bash -c "$(declare -f r); p=$p; r plain-csd-gpu bash /rig/client-plain.sh"
env $CSD SOFT=1 WAIT=6 bash -c "$(declare -f r); p=$p; r plain-csd-sw bash /rig/client-plain.sh"
env QT_STEREO_OFF=1 WAIT=6 bash -c "$(declare -f r); p=$p; r off-ssd-gpu bash /rig/client-qt.sh"
env WAIT=6 bash -c "$(declare -f r); p=$p; r plain-ssd-gpu bash /rig/client-plain.sh"
# raw QOpenGLWindow stereo (the application picks the eye with glDrawBuffer)
env $CSD QT_STEREO_OPENGLWINDOW=1 WAIT=6 bash -c "$(declare -f r); p=$p; r raw-csd-gpu bash /rig/client-qt.sh"
env QT_STEREO_OPENGLWINDOW=1 WAIT=6 bash -c "$(declare -f r); p=$p; r raw-ssd-gpu bash /rig/client-qt.sh"
# Kubrick, Bino
env $CSD WAIT=10 bash -c "$(declare -f r); p=$p; r kubrick-wl-gpu-csd bash /rig/client-kubrick.sh"
env $CSD WAIT=14 bash -c "$(declare -f r); p=$p; r bino-wl-gpu-csd bash /rig/client-bino.sh"
echo MATRIX_DONE
