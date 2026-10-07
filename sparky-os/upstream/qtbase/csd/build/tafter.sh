set -e
cd /work/tsrc
for p in stereo3d-wayland-egl-two-views stereo3d-wayland-egl-eye-slots stereo3d-compositor-rebind-second-texture; do patch -p1 < debian/patches/$p.patch > /dev/null; done
grep -c "contentEyes" src/plugins/platforms/wayland/plugins/hardwareintegration/wayland-egl/qwaylandeglwindow_p.h
cd /work/tbuild && ninja -j4 > /work/tafter.log 2>&1
echo "rc=$?" >> /work/tafter.log; tail -1 /work/tafter.log
