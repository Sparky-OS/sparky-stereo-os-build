#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# Makes the two images the proof runs in (ORDER 51), both from debian:testing by digest with the edition's published round at pin 1001:
#   NAME-red:1    Stereo KWin, Kate and the libraries the plugin needs, no plugin
#   NAME-green:1  the same plus the staged katemark package, installed by apt
# Usage: rig-image.sh NAME BASE_IMAGE REPO STAGE   (apt downloads over https; every later run of the images uses --network none)
set -euo pipefail
NAME=${1:?image name prefix} BASE=${2:?base image} REPO=$(realpath "${3:?edition repository}") STAGE=$(realpath "${4:?stage folder with katemark_*.deb}")
HERE=$(cd "$(dirname "$0")" && pwd)
INSTALL='sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf "Types: deb\nURIs: file:/repo\nSuites: mashtabba\nComponents: main\nSigned-By: /usr/share/keyrings/sparky-stereo-repo.asc\n" > /etc/apt/sources.list.d/sparky.sources
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/sparky
apt-get -y update >/dev/null'
COMMON=(--platform linux/amd64 -v "$REPO":/repo:ro -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro)
docker run --ulimit core=1 --pull=never --name "$NAME-red-build" "${COMMON[@]}" "$BASE" bash -c "set -e
$INSTALL
apt-get -y --no-install-recommends install kwin-wayland kate qt6-wayland dbus dbus-user-session xwayland mesa-libgallium libgl1-mesa-dri \
	fonts-dejavu-core fonts-noto-core fonts-noto-color-emoji python3-gi python3-numpy python3-pil gir1.2-glib-2.0 gcc libc6-dev libwayland-dev wayland-protocols dpkg-dev procps iproute2 libqt6webenginewidgets6 qt6-webengine-data poppler-utils
apt-get -y --no-install-recommends install pkgconf >/dev/null
useradd --uid 1000 --create-home tester
apt-get clean"
docker commit "$NAME-red-build" "$NAME-red:1" >/dev/null
docker rm "$NAME-red-build" >/dev/null
docker run --ulimit core=1 --pull=never --name "$NAME-green-build" "${COMMON[@]}" -v "$STAGE":/stage:ro "$NAME-red:1" bash -c "set -e
cd /tmp && mkdir flat && cp /stage/katemark_*.deb flat/ && cd flat && (dpkg-scanpackages . > Packages 2>/dev/null)
printf 'Types: deb\nURIs: file:/tmp/flat\nSuites: ./\nTrusted: yes\n' > /etc/apt/sources.list.d/stage.sources
printf 'Package: *\nPin: origin \"\"\nPin-Priority: 1002\n' > /etc/apt/preferences.d/stage
apt-get -y update >/dev/null
apt-get -y install katemark"
docker commit "$NAME-green-build" "$NAME-green:1" >/dev/null
docker rm "$NAME-green-build" >/dev/null
