#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
: "${DOCKER_HOST:?Use the lane Docker socket}"
lane=${1:?lane folder}
base=sha256:283f4a3d748a86277c05e12182cde09f7a90a7a04ebea454c1cff01005fba3b0
docker run -d --name pa19-rig --platform linux/amd64 --ulimit core=0 --cpus 2 \
    -v "$lane:/lane" \
    -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
    -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
    "$base" sleep infinity
docker exec pa19-rig sh -c 'sh /run/https-only-apt.sh && apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y install plasma-pa plasma-workspace systemsettings pipewire pipewire-pulse wireplumber pulseaudio-utils xvfb xdotool x11-apps dbus-x11 python3-pil python3-pyatspi at-spi2-core qt6-declarative-dev-tools build-essential cmake ninja-build extra-cmake-modules libkf6pulseaudioqt-dev libplasma-dev libkf6kcmutils-dev libkf6svg-dev libkf6globalaccel-dev libkf6statusnotifieritem-dev libkf6dbusaddons-dev libkf6declarative-dev libcanberra-dev libpulse-dev gettext kded6-dev'
