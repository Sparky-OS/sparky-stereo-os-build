#!/bin/sh
set -eu
proof=${PREPARATION_ROOT:-/w/package-proof}
mkdir -p "$proof"
for pkg in mlt vlc qt6-multimedia libplacebo-dmo; do
 case $pkg in
 mlt) base=mlt_7.40.0-1+stereo3d3; version=7.40.0-1+stereo3d223; extra='--ffmpeg-min-version 10:9.0.2-dmo1+stereo3d6 --gpu-route-min-version 0.1.0' ;;
 vlc) base=vlc_3.0.24-1+stereo3d9; version=3.0.24-1+stereo3d223; extra='--ffmpeg-min-version 10:9.0.2-dmo1+stereo3d6 --gpu-route-min-version 0.1.0' ;;
 qt6-multimedia) base=qt6-multimedia_6.11.2-3+stereo3d6; version=6.11.2-3+stereo3d223; extra='--ffmpeg-min-version 10:9.0.2-dmo1+stereo3d6 --gpu-route-min-version 0.1.0' ;;
 libplacebo-dmo) base=libplacebo-dmo_7.360.1-dmo1; version=2:7.360.1-dmo1+stereo3d223; extra= ;;
 esac
 pub=/pub
 [ "$pkg" != libplacebo-dmo ] || pub=/w/sources
 if [ ! -d "$proof/$pkg" ]; then
  dpkg-source --no-check -x "$pub/$base.dsc" "$proof/$pkg"
 fi
 python3 /build/sparky-os/packages/hardware-decode/prepare.py "$pkg" "$proof/$pkg" --version "$version" $extra
 cd "$proof/$pkg"
 quilt pop -a
 quilt push -a
 cd /w
done
