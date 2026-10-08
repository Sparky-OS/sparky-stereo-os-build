#!/bin/bash
# Source packages: dmo's own source package with only our patches, changelog and packaging changes added
set -eu
export HOME=/tmp/home; mkdir -p $HOME
cd /w/srcpkg
for pkg in ffmpeg mpv; do
  case $pkg in
    ffmpeg) dsc=ffmpeg-dmo_9.0.2-dmo1.dsc; dir=ffmpeg-dmo-9.0.2; built=/w/build-ff/ffmpeg-dmo-9.0.2;;
    mpv) dsc=mpv-dmo_0.41.0-dmo9.dsc; dir=mpv-dmo-0.41.0; built=/w/build-mpv/mpv-dmo-0.41.0;;
  esac
  rm -rf $dir
  cp /w/src/${dsc%%_*}_*.orig.tar.xz* /w/src/$dsc /w/src/${dsc%.dsc}.debian.tar.xz . 2>/dev/null || true
  dpkg-source --no-check --no-preparation -x $dsc
  # our changes, from the build tree's debian/: patches, series, changelog (+ control and rules for mpv)
  cp $built/debian/changelog $dir/debian/changelog
  rm -rf $dir/debian/patches && cp -a $built/debian/patches $dir/debian/patches
  if [ $pkg = mpv ]; then cp $built/debian/control $built/debian/rules $dir/debian/; fi
  (cd $dir && dpkg-source --before-build .)
  dpkg-source -b $dir
  (cd $dir && dpkg-source --after-build .)
done
ls -la
