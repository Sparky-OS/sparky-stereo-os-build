#!/bin/sh
set -eu
mkdir -p /w/package-proof
for pkg in ffmpeg-dmo mpv-dmo mlt kdenlive vlc; do
 case $pkg in
 ffmpeg-dmo) base=ffmpeg-dmo_9.0.2-dmo1+stereo3d5; version=10:9.0.2-dmo1+stereo3d6; extra= ;;
 mpv-dmo) base=mpv-dmo_0.41.0-dmo9+stereo3d3; version=1:0.41.0-dmo9+stereo3d5; extra= ;;
 mlt) base=mlt_7.40.0-1+stereo3d3; version=7.40.0-1+stereo3d5; extra='--ffmpeg-min-version 10:9.0.2-dmo1+stereo3d6' ;;
 kdenlive) base=kdenlive_26.08.1-1+stereo3d3; version=26.08.1-1+stereo3d5; extra='--mlt-min-version 7.40.0-1+stereo3d5' ;;
 vlc) base=vlc_3.0.24-1+stereo3d9; version=3.0.24-1+stereo3d10; extra='--ffmpeg-min-version 10:9.0.2-dmo1+stereo3d6' ;;
 esac
 dpkg-source --no-check -x /pub/$base.dsc /w/package-proof/$pkg
 python3 /w/build-repo/sparky-os/packages/hardware-decode/prepare.py "$pkg" /w/package-proof/$pkg --version "$version" $extra
 cd /w/package-proof/$pkg
 quilt applied
 dpkg-parsechangelog -S Version
 # Validate the Debian patch stack can also unapply cleanly for source packaging.
 quilt pop -a
 quilt push -a
 cd /w
done
