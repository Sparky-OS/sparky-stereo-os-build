#!/bin/bash
# usage: [DEV=1] rtest.sh <name> <test binary under /w> [slots...] : a Qt test in the GPU container under headless KWin; result in out/<name>/client0.{out,log}
n=$1; shift
QMLBIN=/w/run/runtest.sh PEXTRA='{"WAYLAND_DEBUG":"0","QT_QPA_PLATFORM":"wayland"}' /K3D/temp/qtmm-lane/run/rt.sh $n '[["wait",25]]' "$@"
