#!/bin/sh
set -eu
cc -Wall -Wextra -Werror /kit/tests/decode-proof.c -o /w/decode-proof $(pkg-config --cflags --libs libavformat libavcodec libavutil libswscale)
cc -Wall -Wextra -Werror -shared -fPIC /kit/tests/decoder-trace.c -o /w/decoder-trace.so $(pkg-config --cflags --libs libavutil) -ldl
c++ -Wall -Wextra -Werror /kit/tests/qt-proof.cpp -o /w/qt-proof $(pkg-config --cflags --libs Qt6Multimedia Qt6Gui Qt6Core)
cc -Wall -Wextra -Werror /kit/tests/mlt-proof.c -o /w/mlt-proof $(pkg-config --cflags --libs mlt-framework-7)
cc -Wall -Wextra -Werror /kit/tests/vlc-proof.c -o /w/vlc-proof $(pkg-config --cflags --libs libvlc)
cc -Wall -Wextra -Werror /kit/tests/libmpv-proof.c -o /w/libmpv-proof $(pkg-config --cflags mpv) -L/w/mpv-build -Wl,-rpath,/w/mpv-build -lmpv
