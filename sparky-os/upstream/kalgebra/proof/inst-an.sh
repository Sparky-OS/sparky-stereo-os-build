#!/bin/bash
set -eu
export DEBIAN_FRONTEND=noninteractive
cd /o/deb/analitza
apt-get install -y --no-install-recommends ./analitza-common_*stereo3d1_all.deb ./libanalitza9_*stereo3d1_amd64.deb ./libanalitza-dev_*stereo3d1_amd64.deb ./libanalitzagui9_*stereo3d1_amd64.deb ./libanalitzaplot9_*stereo3d1_amd64.deb ./libanalitzawidgets9_*stereo3d1_amd64.deb ./qml6-module-org-kde-analitza_*stereo3d1_amd64.deb 2>&1 | tail -3
dpkg -l | grep analitza | awk '{print $2,$3}'
