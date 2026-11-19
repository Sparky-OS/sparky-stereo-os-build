#!/bin/bash
# Builds the two images of the Sound Quality page rows: lab22-page-stock:1 (the audio-stock image with Debian's plasma-pa) and
# lab22-page-ours:1 (the audio-ours image with the edition's plasma-pa, the one with the Sound Quality page, installed from its .deb).
#   build-page.sh SKILLS_CLONE PLASMA_PA_DEB      needs DOCKER_HOST (the lane's socket) and the two audio images (build-audio.sh)
# SKILLS_CLONE holds skills/audio/bench/page-rig, PLASMA_PA_DEB is the plasma-pa package of the edition (staged; apt resolves its
# dependencies from Debian). Both images get qml6 (the package qml-qt6) and the page rig's files in /opt/lab/rig, over the audio rig's.
# Containers are named lab22-build-*, started with --pull=never, apt over HTTPS only.
set -euo pipefail
SK=$(realpath "$1") DEB=$(realpath "$2")
: "${DOCKER_HOST:?set DOCKER_HOST to the lane socket}"
HELP=/K3D/partners/https-only-apt.sh
PAGE=$SK/skills/audio/bench/page-rig
apt_mounts=(-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HELP":/run/https-only-apt.sh:ro)
for side in stock ours; do
	docker rm -f lab22-build-page-$side >/dev/null 2>&1 || true
	pkg="plasma-pa"
	extra=()
	if [ $side = ours ]; then pkg=/deb/$(basename "$DEB"); extra=(-v "$(dirname "$DEB")":/deb:ro); fi
	docker run --name lab22-build-page-$side --pull=never --ulimit core=0 --cpus 4 "${apt_mounts[@]}" "${extra[@]}" -v "$PAGE":/page:ro lab22-audio-$side:1 sh -c '
set -e
sh /run/https-only-apt.sh
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install '"$pkg"' qml-qt6 >/dev/null
cp /page/harness.qml /page/qml-steps.sh /page/steps-flow.json /page/steps-dump.json /opt/lab/rig/
cp /page/rig-alsa-nodes.lua /usr/share/wireplumber/scripts/rig-alsa-nodes.lua
apt-get clean
dpkg-query -W plasma-pa sparky-stereo-audio qml-qt6 2>&1 || true
'
	docker commit lab22-build-page-$side lab22-page-$side:1 >/dev/null
	docker rm lab22-build-page-$side >/dev/null
done
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep '^lab22-page'
