#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update -qq
cd /w/dmo-debs-i386
apt-get download ffmpeg:i386=10:9.0.2-dmo1 libavcodec63:i386=10:9.0.2-dmo1 libavdevice63:i386=10:9.0.2-dmo1 libavfilter12:i386=10:9.0.2-dmo1 libavformat63:i386=10:9.0.2-dmo1 libavutil61:i386=10:9.0.2-dmo1 libswresample7:i386=10:9.0.2-dmo1 libswscale10:i386=10:9.0.2-dmo1 libavcodec-dev:i386=10:9.0.2-dmo1 libavutil-dev:i386=10:9.0.2-dmo1 2>&1 | tail -5
chown -R 1000:1000 /w/dmo-debs-i386
ls -la /w/dmo-debs-i386
