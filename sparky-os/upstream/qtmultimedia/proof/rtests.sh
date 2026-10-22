#!/bin/bash
# usage: rtests.sh <tree>
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
t=$1
rm -rf ${SPARKY_SCRATCH:?}/qtmm-lane/out/tests-$t
QMLBIN=/w/run/dummy.sh PEXTRA='{"WAYLAND_DEBUG":"0"}' ${SPARKY_SCRATCH:?}/qtmm-lane/run/rt.sh tests-$t-run '[["sh","/w/run/alltests.sh '$t'"]]'
