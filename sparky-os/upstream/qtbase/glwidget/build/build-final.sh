set -e
cd /work/pkg/qt6-base-6.11.2+dfsg
rm -f ../*stereo3d4_*.deb ../*stereo3d4_*.buildinfo ../*stereo3d4_*.changes
cd obj-x86_64-linux-gnu
ninja -j4 > /work/ninja3.log 2>&1
echo "ninja rc=$?" >> /work/ninja3.log
cd ..
rm -f debian/files debian/*.debhelper.log
export DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=4"
dpkg-buildpackage -us -uc -b -nc -j4 > /work/build3.log 2>&1
echo "rc=$?" >> /work/build3.log
