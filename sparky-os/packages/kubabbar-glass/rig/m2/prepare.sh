#!/bin/bash
set -euo pipefail
lane=$(cd "$(dirname "$0")/../../.." && pwd)
[ -S "$lane/docker.sock" ] && export DOCKER_HOST="unix://$lane/docker.sock" || true
printf '%s\n' classic-look-m2-prepare classic-look-rig:m2 >> "$lane/.artifacts"
trap 'docker rm classic-look-m2-prepare >/dev/null 2>&1 || true' EXIT
docker run --name classic-look-m2-prepare --platform linux/amd64 --cpus 4 --user 0:0 --entrypoint /bin/sh \
 -v /K3D/temp/sparky-os/repo:/var/local/sparky-stereo-repo:ro classic-look-rig:m1-oxygen -c '
 set -e
 apt-get update
 DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install g++ pkg-config qt6-base-dev qtbase5-dev qtwayland5 python3-pyqt5 gtk-4-examples gir1.2-gtk-4.0 kde-config-gtk-style xsettingsd qt5-style-kvantum qt6-style-kvantum breeze-gtk-theme xwayland kpackagetool6
 '
docker logs classic-look-m2-prepare > "$lane/theme/evidence/m2/prepare.log" 2>&1
docker commit classic-look-m2-prepare classic-look-rig:m2
