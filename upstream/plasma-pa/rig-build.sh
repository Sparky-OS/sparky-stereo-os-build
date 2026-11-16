#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
: "${DOCKER_HOST:?Use the lane Docker socket}"
docker exec pa19-rig sh -c 'id rig >/dev/null 2>&1 || useradd -m -u 1000 rig; mkdir -p /work; chown 1000:1000 /work'
docker exec --user 1000:1000 pa19-rig sh -c '
    cp -r /lane/src/plasma-pa /work/plasma-pa
    rm -rf /work/plasma-pa/.git
    cmake -S /work/plasma-pa -B /work/build -G Ninja -DBUILD_DOC=OFF -DBUILD_TESTING=ON -DCMAKE_INSTALL_PREFIX=/opt/order19
    cmake --build /work/build -j2
'
docker exec pa19-rig cmake --install /work/build
docker exec pa19-rig sh -c '
    cd /work/plasma-pa
    patch -p1 < /lane/src/sparky-stereo-os-build/sparky-os/translations/plasma-pa-virtual-streams.po.patch
    for lang in pl pt_BR fr de es ja ko zh_CN zh_TW; do
        for domain in kcm_pulseaudio plasma_applet_org.kde.plasma.volume; do
            msgfmt --check --check-format -o /opt/order19/share/locale/$lang/LC_MESSAGES/$domain.mo po/$lang/$domain.po || exit
        done
    done
'
