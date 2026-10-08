set -e
bash /work/pkg.sh 1 6.11.2+dfsg-5+stereo3d4~toggles1 > /work/pkg-prep.log 2>&1
cd /work/pkg/qt6-base-6.11.2+dfsg
export DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=4"
dpkg-buildpackage -us -uc -b -j4 > /work/build1.log 2>&1
echo "rc=$?" >> /work/build1.log
