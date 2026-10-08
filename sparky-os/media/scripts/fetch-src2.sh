#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
cd /w/src
apt-get source --download-only ffmpeg-dmo mpv-dmo 2>&1 | tail -20
ls -la /w/src
