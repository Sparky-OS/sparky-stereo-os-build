#!/bin/bash
set -euo pipefail
[[ -e /.dockerenv ]]
HERE=$(cd "$(dirname "$0")" && pwd)
sdk=${HEADLESS_SDK:-$PWD/work/sdk-extra}
export LD_LIBRARY_PATH=$sdk/usr/lib/x86_64-linux-gnu
c++ -std=c++20 "$HERE/observer.cpp" -o "${TIMELINE_OBSERVER:-$PWD/work/timeline-observer}" $(pkg-config --cflags --libs Qt6Gui Qt6Core) -I$sdk/usr/include/KF6/KScreen -L$sdk/usr/lib/x86_64-linux-gnu -Wl,-rpath-link=$sdk/usr/lib/x86_64-linux-gnu -lKF6ScreenDpms
