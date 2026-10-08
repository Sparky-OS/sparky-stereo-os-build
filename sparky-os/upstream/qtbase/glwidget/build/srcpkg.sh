set -e
cd /work && rm -rf srcpkg && mkdir srcpkg && cd srcpkg
cp ../pkg/qt6-base_6.11.2+dfsg-5+stereo3d3.dsc ../pkg/qt6-base_6.11.2+dfsg-5+stereo3d3.debian.tar.xz ../pkg/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source --skip-patches -x qt6-base_6.11.2+dfsg-5+stereo3d3.dsc qt6-base-6.11.2+dfsg > /dev/null
cd qt6-base-6.11.2+dfsg
cp /work/patches/stereo3d-native-stereo-opengl-widget.patch /work/patches/stereo3d-wayland-defer-stereo-egl-surface.patch debian/patches/
printf 'stereo3d-native-stereo-opengl-widget.patch\nstereo3d-wayland-defer-stereo-egl-surface.patch\n' >> debian/patches/series
cp /work/pkg/qt6-base-6.11.2+dfsg/debian/changelog debian/changelog
cd ..
dpkg-source -b qt6-base-6.11.2+dfsg
ls -la
