cd /work/src/qt6-base-6.11.2+dfsg
dpkg-buildpackage -S -d -us -uc -sa > /work/srcbuild.log 2>&1; echo rc=$? >> /work/srcbuild.log
tail -5 /work/srcbuild.log
