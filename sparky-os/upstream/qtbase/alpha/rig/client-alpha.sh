#!/bin/bash
# qt-alpha-test under the EGL shim (compiled here, prints the config of every window surface)
export QT_STEREO_HOLD_MS=${QT_STEREO_HOLD_MS:-14000}
gcc -shared -fPIC -O1 -o /tmp/eglshim.so /rig/eglshim.c -ldl -lEGL || exit 9
LD_PRELOAD=/tmp/eglshim.so exec /usr/local/bin/qt-alpha-test
