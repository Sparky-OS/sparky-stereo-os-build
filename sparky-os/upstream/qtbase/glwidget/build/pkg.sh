# usage in container (cwd /work/pkg): pkg.sh <with-toggles: 1|0> <version>
set -e
cd /work/pkg
rm -rf qt6-base-6.11.2+dfsg
dpkg-source -x qt6-base_6.11.2+dfsg-5+stereo3d3.dsc > /work/pkg-x.log 2>&1
cd qt6-base-6.11.2+dfsg
cp /work/patches/stereo3d-native-stereo-opengl-widget.patch /work/patches/stereo3d-wayland-defer-stereo-egl-surface.patch debian/patches/
printf 'stereo3d-native-stereo-opengl-widget.patch\nstereo3d-wayland-defer-stereo-egl-surface.patch\n' >> debian/patches/series
if [ "$1" = 1 ]; then cp /work/patches/zz-toggles.patch debian/patches/; echo zz-toggles.patch >> debian/patches/series; fi
export QUILT_PATCHES=debian/patches
quilt push -a 2>&1 | tail -4
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL="Capitain_Jack@yahoo.com"
dch -v ${2} -D unstable --force-distribution "Sparky Stereo OS: a stereo QOpenGLWidget is a stereo window of its own on Wayland. New patch stereo3d-native-stereo-opengl-widget: a QOpenGLWidget that asks for stereo (its own format or the default format) is shown in a native window with a stereo format, a subsurface placed at the widget; the top-level window and the other widgets stay an ordinary one-eye surface, and a top-level window is stereo only when its own widget renders stereo (platform capability StereoNativeWindows, reported by Wayland when the EGL implementation has stereo surfaces). New patch stereo3d-wayland-defer-stereo-egl-surface: the EGL surface of a stereo window is created when the window is shown and sized, not at Qt's default 100x30, so a stereo window is not collapsed by the compositor after a first frame at the wrong size. Mono windows, xcb and every other platform are unchanged."
head -4 debian/changelog
