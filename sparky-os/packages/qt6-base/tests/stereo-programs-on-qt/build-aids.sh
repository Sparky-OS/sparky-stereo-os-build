#!/bin/bash
# build-aids.sh OUT -- inside an image with Qt 6's development files and gcc (sc50i-rig:qt863-pub): builds the test aids of
# row 863 part A into OUT: r863-probe.so (this folder), gl-shim.so (sparky-os/upstream/kalgebra/proof/gl-shim.c, the
# KAlgebra and Kalzium proofs' GL record), kubrick-shim-r863.so (this folder's copy of the Qt rig's Kubrick shim) and
# frame-check (A4's plain window).
# The folder is mounted at /t and build main's sparky-os/upstream at /u.
set -euo pipefail
out=$1
g++ -shared -fPIC -std=c++17 -O1 -Wall /t/r863-probe.cpp $(pkg-config --cflags --libs Qt6Widgets) -o "$out/r863-probe.so"
gcc -shared -fPIC -O1 -o "$out/gl-shim.so" /u/kalgebra/proof/gl-shim.c -ldl -lm
gcc -shared -fPIC -O1 -o "$out/kubrick-shim-r863.so" /t/kubrick-shim-r863.c -ldl
g++ -std=c++17 -O1 -Wall /t/frame-check.cpp $(pkg-config --cflags --libs Qt6Widgets) -o "$out/frame-check"
ls -la "$out"
