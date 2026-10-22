#!/bin/bash
# run image: plank-run:R (headless KWin from our repo etc.) + the QML runtime tools for a test app
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker rm -f qtmm-runimg >/dev/null 2>&1
docker run --name qtmm-runimg --platform linux/amd64 --cpus 4 -v ${SPARKY_REPO_DIR:?}:/repo:ro -v ${SPARKY_SCRATCH:?}/qtmm-lane/run/pin:/pin:ro -e DEBIAN_FRONTEND=noninteractive qtmm-run:2 bash -c '
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update >/dev/null 2>&1
apt-get -y --allow-downgrades install dragonplayer qml6-module-qt-labs-animation qml6-module-qtquick-dialogs qml6-module-org-kde-kirigami qml6-module-org-kde-desktop qml-qt6 qt6-declarative-dev-tools qml6-module-qtquick qml6-module-qtquick-window qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-templates qml6-module-qtmultimedia strace wayland-utils 2>&1 | tail -3
rm -f /etc/apt/sources.list.d/zrepo.list'
docker commit qtmm-runimg qtmm-run:3 >/dev/null; docker rm qtmm-runimg >/dev/null; echo imgdone
