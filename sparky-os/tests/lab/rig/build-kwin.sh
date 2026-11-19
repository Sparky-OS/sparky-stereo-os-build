#!/bin/bash
# Builds the two compositor images of the lab: lab22-kwin-stock:1 (Debian's KWin and Mesa) and lab22-kwin-ours:1 (the same
# packages from the edition's published tree, pinned above Debian's: Stereo KWin, its Mesa, Qt and the stereo libraries).
#   build-kwin.sh REPO_TREE        needs DOCKER_HOST (the lane socket). The tree is mounted read only.
set -euo pipefail
TREE=$(realpath "$1")
: "${DOCKER_HOST:?set DOCKER_HOST to the lane socket}"
HELP=/K3D/partners/https-only-apt.sh
apt_mounts=(-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HELP":/run/https-only-apt.sh:ro)
PKGS="ca-certificates kwin-wayland libkscreen-bin qt6-wayland mesa-libgallium libgl1-mesa-dri libegl-mesa0 dbus dbus-bin gcc libc6-dev pkg-config libwayland-bin libwayland-dev wayland-protocols libegl-dev libgl-dev python3 python3-pil"
for side in stock ours; do
	docker rm -f lab22-build-kwin-$side >/dev/null 2>&1 || true
	extra=""
	docker run --name lab22-build-kwin-$side --pull=never --ulimit core=0 --cpus 4 "${apt_mounts[@]}" -v "$TREE":/repo:ro \
		-e SIDE=$side -e PKGS="$PKGS $extra" debian:testing sh -c '
set -e
sh /run/https-only-apt.sh
if [ "$SIDE" = ours ]; then
	echo "deb [trusted=yes] file:///repo mashtabba main" > /etc/apt/sources.list.d/lab22-tree.list
	printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/lab22
fi
apt-get update -qq 2>&1 | tail -1
DEBIAN_FRONTEND=noninteractive apt-get -y -qq --no-install-recommends install $PKGS >/dev/null 2>/tmp/err || { tail -20 /tmp/err; exit 1; }
rm -f /etc/apt/sources.list.d/lab22-tree.list /etc/apt/preferences.d/lab22
apt-get clean
dpkg-query -W -f="\${Package}\t\${Version}\n" kwin-wayland libkwin6 libgl1-mesa-dri libkscreen-bin 2>/dev/null | sed "s/^/$SIDE /" || true
dpkg-query -W -f="\${Package}\t\${Version}\n" > /etc/lab22-packages.txt
'
	docker commit lab22-build-kwin-$side lab22-kwin-$side:1 >/dev/null
	docker rm lab22-build-kwin-$side >/dev/null
done
docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep '^lab22-kwin'
