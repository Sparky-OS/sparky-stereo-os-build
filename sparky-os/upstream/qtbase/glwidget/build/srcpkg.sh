set -e
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
cd /work && rm -rf srcpkg && mkdir srcpkg && cd srcpkg
cp ../pkg/qt6-base_6.11.2+dfsg-5+stereo3d3.dsc ../pkg/qt6-base_6.11.2+dfsg-5+stereo3d3.debian.tar.xz ../pkg/qt6-base_6.11.2+dfsg.orig.tar.xz .
dpkg-source --skip-patches -x qt6-base_6.11.2+dfsg-5+stereo3d3.dsc qt6-base-6.11.2+dfsg > /dev/null
cd qt6-base-6.11.2+dfsg
cp /work/patches/stereo3d-native-stereo-opengl-widget.patch /work/patches/stereo3d-wayland-defer-stereo-egl-surface.patch debian/patches/
printf 'stereo3d-native-stereo-opengl-widget.patch\nstereo3d-wayland-defer-stereo-egl-surface.patch\n' >> debian/patches/series
cp /work/pkg/qt6-base-6.11.2+dfsg/debian/changelog debian/changelog
cd ..
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" qt6-base-6.11.2+dfsg
dpkg-source -b qt6-base-6.11.2+dfsg
ls -la
