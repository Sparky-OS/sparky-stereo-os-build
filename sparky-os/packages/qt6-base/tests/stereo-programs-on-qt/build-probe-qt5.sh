#!/bin/bash
# build-probe-qt5.sh OUT -- inside a container of the part-A image with apt's sources (prelude-fc.sh) and the network:
# installs Qt 5's development files and builds r863-probe.cpp against Qt 5 into OUT/r863-probe-qt5.so, for VLC Stereo
# (a Qt 5 program). The folder is mounted at /t. The container is thrown away.
set -euo pipefail
. /tools/prelude-fc.sh > /dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends qtbase5-dev g++ pkg-config > /out/qt5-dev-install.txt 2>&1
g++ -shared -fPIC -std=c++17 -O1 -Wall /t/r863-probe.cpp $(pkg-config --cflags --libs Qt5Widgets) -o /out/r863-probe-qt5.so
nm -D --defined-only /out/r863-probe-qt5.so | grep startup_hook
