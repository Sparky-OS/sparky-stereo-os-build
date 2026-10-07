#!/bin/bash
docker rm -f qtmm-rundeb >/dev/null 2>&1
docker run --name qtmm-rundeb --platform linux/amd64 --cpus 2 -e DEBIAN_FRONTEND=noninteractive qtmm-run:3 bash -c '
rm -f /etc/apt/preferences.d/sparky-stereo /etc/apt/sources.list.d/zrepo.list
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install --no-install-recommends libqt6multimedia6=6.11.2-3 libqt6multimediawidgets6=6.11.2-3 libqt6spatialaudio6=6.11.2-3 qml6-module-qtmultimedia=6.11.2-3 2>&1 | tail -4
dpkg -l | grep -E "libqt6multimedia6|qml6-module-qtmultimedia|dragonplayer" | awk "{print \$2, \$3}"'
docker commit qtmm-rundeb qtmm-run:deb >/dev/null; docker rm qtmm-rundeb >/dev/null; echo imgdone
