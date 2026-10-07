#!/bin/bash
# usage: rtests.sh <tree>
t=$1
rm -rf /K3D/temp/qtmm-lane/out/tests-$t
QMLBIN=/w/run/dummy.sh PEXTRA='{"WAYLAND_DEBUG":"0"}' /K3D/temp/qtmm-lane/run/rt.sh tests-$t-run '[["sh","/w/run/alltests.sh '$t'"]]'
