set -e
cd /work/tsrc
for p in stereo3d-compositor-rebind-second-texture stereo3d-wayland-egl-eye-slots stereo3d-wayland-egl-two-views; do patch -R -p1 < debian/patches/$p.patch > /dev/null; done
grep -c "contentEyes\|supportsStereo" src/plugins/platforms/wayland/plugins/hardwareintegration/wayland-egl/qwaylandeglwindow_p.h src/plugins/platforms/wayland/plugins/hardwareintegration/wayland-egl/qwaylandeglwindow.cpp || true
cd /work/tbuild && ninja -j4 > /work/tbefore.log 2>&1
echo "rc=$?" >> /work/tbefore.log; tail -2 /work/tbefore.log | cut -c1-150
