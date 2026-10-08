set -e
cd /work/pkg/qt6-base-6.11.2+dfsg
export QUILT_PATCHES=debian/patches
echo "--- before"; quilt applied | tail -4
FILES=$(grep -h "^+++ b/" /work/patches/stereo3d-native-stereo-opengl-widget.patch /work/patches/stereo3d-wayland-defer-stereo-egl-surface.patch /work/patches/zz-toggles.patch | sed 's#^+++ b/##' | sort -u)
for f in $FILES; do echo "$f $(stat -c %Y $f)"; done > /work/mtimes.txt
cat /work/mtimes.txt
cp /work/patches/zz-toggles.patch debian/patches/zz-toggles.patch
grep -q zz-toggles debian/patches/series || echo zz-toggles.patch >> debian/patches/series
quilt pop stereo3d-translucent-keeps-requested-depth.patch 2>&1 | tail -2
cp /work/patches/stereo3d-native-stereo-opengl-widget.patch /work/patches/stereo3d-wayland-defer-stereo-egl-surface.patch debian/patches/
rm -f debian/patches/zz-toggles.patch
sed -i '/zz-toggles/d' debian/patches/series
quilt push -a 2>&1 | tail -4
while read f t; do touch -d @$t $f; done < /work/mtimes.txt
touch src/widgets/kernel/qwidget.cpp src/plugins/platforms/wayland/plugins/hardwareintegration/wayland-egl/qwaylandeglwindow.cpp
grep -n "QT_STEREO" src/widgets/kernel/qwidget.cpp src/plugins/platforms/wayland/plugins/hardwareintegration/wayland-egl/qwaylandeglwindow.cpp || echo "no toggles left"
quilt applied | tail -3
