#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
cd /w/dmo-debs
apt-get download ffmpeg=10:9.0.2-dmo1 ffplay=10:9.0.2-dmo1 libavcodec63=10:9.0.2-dmo1 libavcodec-dev=10:9.0.2-dmo1 libavdevice63=10:9.0.2-dmo1 libavdevice-dev=10:9.0.2-dmo1 libavfilter12=10:9.0.2-dmo1 libavfilter-dev=10:9.0.2-dmo1 libavformat63=10:9.0.2-dmo1 libavformat-dev=10:9.0.2-dmo1 libavutil61=10:9.0.2-dmo1 libavutil-dev=10:9.0.2-dmo1 libswresample7=10:9.0.2-dmo1 libswresample-dev=10:9.0.2-dmo1 libswscale10=10:9.0.2-dmo1 libswscale-dev=10:9.0.2-dmo1 mpv=1:0.41.0-dmo9 libmpv2=1:0.41.0-dmo9 libmpv-dev=1:0.41.0-dmo9 2>&1 | tail -30
chown -R 1000:1000 /w/dmo-debs
ls -la /w/dmo-debs
