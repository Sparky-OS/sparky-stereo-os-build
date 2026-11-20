#!/bin/bash
# Builds the two audio images of the lab: lab22-audio-stock:1 (Debian's PipeWire and WirePlumber, the rig's fake sound
# devices) and lab22-audio-ours:1 (the same with the edition's sparky-stereo-audio installed by apt).
#   build-audio.sh SKILLS_CLONE STAGE_DIR REPO_TREE      needs DOCKER_HOST (the lane's socket)
# SKILLS_CLONE holds skills/audio/bench/rig, STAGE_DIR the sparky-stereo-audio .deb files (a flat apt repository with a
# Packages file), REPO_TREE the published tree (read only; sparky-stereo-problems comes from it).
# Containers are named lab22-build-*, started with --pull=never, apt over HTTPS only.
set -euo pipefail
SK=$(realpath "$1") STAGE=$(realpath "$2") TREE=$(realpath "$3")
RIG=$SK/skills/audio/bench/rig
: "${DOCKER_HOST:?set DOCKER_HOST to the lane socket}"
BASE=${LAB_BASE_IMAGE:-debian:testing}
HELP=/K3D/partners/https-only-apt.sh
apt_mounts=(-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HELP":/run/https-only-apt.sh:ro)
docker rm -f lab22-build-stock lab22-build-ours >/dev/null 2>&1 || true
docker run --name lab22-build-stock --pull=never --ulimit core=1 --cpus 4 "${apt_mounts[@]}" -v "$RIG":/src:ro "$BASE" sh -c '
set -e
sh /run/https-only-apt.sh
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install pipewire pipewire-bin wireplumber pipewire-pulse pulseaudio-utils \
  python3 gcc libc6-dev libasound2-dev libasound2t64 dbus dbus-user-session ca-certificates procps >/dev/null
mkdir -p /opt/sa631 /run/sa631 /opt/lab/rig /home/rig
cp -r /src/. /opt/lab/rig/
cp -r /src/proc-asound /opt/sa631/proc-asound
sh /src/build-plugin.sh /opt/sa631
cp /src/asound.conf /etc/asound.conf
cp /src/rig-alsa-nodes.lua /usr/share/wireplumber/scripts/
mkdir -p /etc/wireplumber/wireplumber.conf.d
cp /src/90-sa631-rig.conf /etc/wireplumber/wireplumber.conf.d/
useradd -u 1001 -m -d /home/rig rig 2>/dev/null || true
chmod 1777 /run/sa631
apt-get -y -qq purge gcc libc6-dev libasound2-dev >/dev/null 2>&1 || true
apt-get -y -qq autoremove --purge >/dev/null 2>&1 || true
apt-get clean
'
docker commit lab22-build-stock lab22-audio-stock:1 >/dev/null
docker rm lab22-build-stock >/dev/null
docker run --name lab22-build-ours --pull=never --ulimit core=1 --cpus 4 "${apt_mounts[@]}" -v "$STAGE":/stage:ro -v "$TREE":/repo:ro lab22-audio-stock:1 sh -c '
set -e
sh /run/https-only-apt.sh
echo "deb [trusted=yes] file:///stage ./" > /etc/apt/sources.list.d/lab22-stage.list
echo "deb [trusted=yes] file:///repo mashtabba main" > /etc/apt/sources.list.d/lab22-tree.list
printf "Package: *\nPin: origin \"\"\nPin-Priority: 100\n\nPackage: sparky-stereo-audio\nPin: version *\nPin-Priority: 900\n" > /etc/apt/preferences.d/lab22
apt-get update -qq 2>&1 | tail -2
apt-cache policy sparky-stereo-audio sparky-stereo-problems pipewire wireplumber | grep -E "^[a-z]|Candidate"
SPARKY_STEREO_AUDIO_PROC=/opt/sa631/proc-asound DEBIAN_FRONTEND=noninteractive apt-get -y -qq install sparky-stereo-audio 2>&1 | tail -5
rm -f /etc/apt/sources.list.d/lab22-*.list /etc/apt/preferences.d/lab22
dpkg -l sparky-stereo-audio pipewire wireplumber | tail -3
'
docker commit lab22-build-ours lab22-audio-ours:1 >/dev/null
docker rm lab22-build-ours >/dev/null
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep '^lab22-'
