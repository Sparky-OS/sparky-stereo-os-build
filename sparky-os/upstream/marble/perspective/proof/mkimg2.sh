#!/bin/bash
# marble-build:2 = marble-build:1 + libfaketime; marble-stock:2 = + Debian's own marble and marble-qt (4:26.04.0-2), no repository, no pin
set -e
docker rm -f marble-img2 >/dev/null 2>&1 || true
docker run --name marble-img2 --platform linux/amd64 --cpus 4 -e DEBIAN_FRONTEND=noninteractive marble-build:1 bash -c 'apt-get -y update >/dev/null 2>&1; apt-get -y install libfaketime 2>&1 | tail -1'
docker commit marble-img2 marble-build:2 >/dev/null; docker rm marble-img2 >/dev/null
docker run --name marble-img3 --platform linux/amd64 --cpus 4 -e DEBIAN_FRONTEND=noninteractive marble-build:2 bash -c 'rm -f /etc/apt/preferences.d/sparky-stereo; apt-get -y install marble marble-qt 2>&1 | tail -2; dpkg -l marble marble-qt libmarblewidget-qt6-28 | grep ^ii | awk "{print \$2,\$3}"'
docker commit marble-img3 marble-stock:2 >/dev/null; docker rm marble-img3 >/dev/null
echo img2done
