set -e
cd /work/src/qt6-base-6.11.2+dfsg
patch -R -p1 < debian/patches/stereo3d-wayland-no-csd-stereo-window.patch >/dev/null
patch -R -p1 < debian/patches/stereo3d-wayland-egl-two-views.patch >/dev/null
grep -c isStereoOpenGLWindow src/plugins/platforms/wayland/qwaylandwindow.cpp || true
cd /work/tbuild && ninja -j4 > /work/tbuild3.log 2>&1
echo "rc=$?" >> /work/tbuild3.log; tail -2 /work/tbuild3.log | cut -c1-150
