#!/bin/sh
set -eu
/w/bin/dmo-setup.sh
cd /w/src
echo "=== policy"; apt-cache policy ffmpeg mpv libavcodec63 libmpv2 | head -60
echo "=== showsrc"; apt-cache showsrc ffmpeg mpv | grep -E '^(Package|Version|Directory|Binary|Format|Vcs|Maintainer|Build-Depends)' | cut -c1-400
