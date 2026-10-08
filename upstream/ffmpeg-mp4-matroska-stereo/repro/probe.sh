#!/bin/sh
cd /out
for f in probe-original probe-no-vexu probe-no-st3d probe-vexu-first; do
  printf "%-20s " $f; ffprobe -hide_banner $f.mp4 2>&1 | grep -E "Stereo 3D|Invalid|invalid|Error|error" | sed 's/^ *//' | tr '\n' '|'; echo
done
