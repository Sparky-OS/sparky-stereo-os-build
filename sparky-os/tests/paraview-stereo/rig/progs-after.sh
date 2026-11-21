#!/bin/bash
# After pv-after.sh: the rows of the programs that load vtk9 (vtk-progs-batch.sh), when / has 5 GB free for their images.
S=/var/lib/sparky-lanes/science-paraview-50f; cd $S
p=${1:?the PID of pv-after.sh}; while kill -0 "$p" 2>/dev/null; do sleep 30; done
free=$(df -B1M --output=avail / | tail -1 | tr -d ' ')
if [ "$free" -ge 5120 ]; then rig/vtk-progs-batch.sh > work/vtk-progs.log 2>&1; echo "programs rows done" >> work/vtk-progs.log
else echo "programs rows not started: / has $free MB free, under 5 GB for their three images" | tee work/vtk-progs.log; fi
