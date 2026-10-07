cd /work/src/qt6-base-6.11.2+dfsg
export DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=4"
dpkg-buildpackage -us -uc -b -nc -j4 > /work/build2.log 2>&1
echo "rc=$?" >> /work/build2.log
