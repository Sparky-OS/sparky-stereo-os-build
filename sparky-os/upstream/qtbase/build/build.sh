cd /work/src/qt6-base-6.11.2+dfsg
uname -m
export DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=4"
dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1
echo "rc=$?" >> /work/build.log
