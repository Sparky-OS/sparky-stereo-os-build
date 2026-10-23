#!/bin/sh
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
set -eu
# /kit is hardware-decode; every include and linked engine comes from installed packages.
mkdir -p /w/probes
cc -Wall -Wextra -Werror /kit/tests/decode-proof.c -o /w/probes/decode-proof $(pkg-config --cflags --libs libavformat libavcodec libavutil libswscale)
cc -Wall -Wextra -Werror -shared -fPIC /kit/tests/decoder-trace.c -o /w/probes/decoder-trace.so $(pkg-config --cflags --libs libavutil) -ldl
c++ -Wall -Wextra -Werror /kit/tests/qt-proof.cpp -o /w/probes/qt-proof $(pkg-config --cflags --libs Qt6Multimedia Qt6Gui Qt6Core)
cc -Wall -Wextra -Werror /kit/tests/mlt-proof.c -o /w/probes/mlt-proof $(pkg-config --cflags --libs mlt-framework-7)
cc -Wall -Wextra -Werror /kit/tests/vlc-proof.c -o /w/probes/vlc-proof $(pkg-config --cflags libvlc) -L/usr/lib/x86_64-linux-gnu/vlc-stereo -Wl,-rpath,/usr/lib/x86_64-linux-gnu/vlc-stereo -lvlc
cc -Wall -Wextra -Werror /kit/tests/libmpv-proof.c -o /w/probes/libmpv-proof $(pkg-config --cflags --libs mpv)
cc -Wall -Wextra -Werror /kit/tests/routing/device-choice.c -o /w/device-choice $(pkg-config --cflags --libs vulkan libplacebo) -ldl
cc -Wall -Wextra -Werror /kit/tests/routing/decoder-choice.c -o /w/decoder-choice $(pkg-config --cflags --libs media-gpu-route libavformat libavcodec libavutil)
cc -Wall -Wextra -Werror -shared -fPIC /kit/tests/routing/compositor-device.c -o /w/compositor-device.so $(pkg-config --cflags --libs libdrm) -ldl
ldd /usr/bin/mpv /w/probes/qt-proof /w/probes/mlt-proof /w/probes/vlc-proof /w/probes/libmpv-proof > /w/probes/installed-linkage.log
if grep -E '/(prev|w)/(.*-build|route-prefix)' /w/probes/installed-linkage.log; then
 echo 'Diagnostic library used in installed qualification' >&2
 exit 1
fi
