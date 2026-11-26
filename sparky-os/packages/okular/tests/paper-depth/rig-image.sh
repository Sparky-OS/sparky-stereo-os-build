#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# rig-image.sh BASE NAME REPO_DIR [DEB_DIR...] -- the paper depth proof's image: Debian testing (BASE, pulled by digest) with
# the edition's published tree (REPO_DIR, a local copy, as a file: source pinned at 1001), Stereo KWin, kscreen-doctor,
# Okular, Qt's development files, g++, the rig's Python and KWin's Breeze decoration (windows framed by KWin, as in a session); then, from each DEB_DIR, the .deb files of the packages under
# test installed by apt over it: the newer build of every package the image already has, and okular.
# The edition's local names map to 127.0.0.1, so no packet reaches the local network; sparky-stereo.sources, which
# sparky-stereo-apt adds, is removed after any install. NAME is committed from the container; PREFIX names the container.
# SKIP='REGEX': the packages under test whose names match are left as published (the KWin-older red row).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=$1 NAME=$2 REPO=$(cd "$3" && pwd -P); shift 3
PREFIX=${PREFIX:-paper-depth}
mounts=()
i=0
for d in "$@"; do mounts+=(--mount "type=bind,src=$(cd "$d" && pwd -P),dst=/debs/$i,readonly"); i=$((i + 1)); done
container=$PREFIX-rig-image
docker run --name "$container" --pull=never --ulimit core=1 --cpus 4 --platform linux/amd64 \
	--add-host repo.sparkyos.org:127.0.0.1 --add-host d2server:127.0.0.1 \
	--mount "type=bind,src=$REPO,dst=/repo,readonly" "${mounts[@]}" \
	--mount type=bind,src=/usr/share/keyrings/deb-multimedia-keyring.pgp,dst=/usr/share/keyrings/deb-multimedia-keyring.pgp,readonly \
	--mount type=bind,src=/etc/ssl/certs/ca-certificates.crt,dst=/run/host-ca.crt,readonly \
	--mount "type=bind,src=$HERE/../../../../../tools/https-only-apt.sh,dst=/run/https-only-apt.sh,readonly" \
	-e "SKIP=${SKIP:-}" "$BASE" bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
sh /run/https-only-apt.sh
cp /repo/sparky-stereo-repo.asc /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
printf "deb [signed-by=/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc] file:/repo mashtabba main\n" > /etc/apt/sources.list.d/edition.list
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/edition
apt-get -qq update
apt-get -y -qq --no-install-recommends install kwin-wayland libkscreen-bin okular qt6-base-dev g++ pkg-config python3-gi \
	gir1.2-glib-2.0 python3-numpy python3-pil dbus libgl1-mesa-dri libegl-mesa0 fonts-dejavu-core procps \
	kwin-style-breeze breeze-cursor-theme > /tmp/install.log 2>&1 \
	|| { tail -30 /tmp/install.log; exit 1; }
rm -f /etc/apt/sources.list.d/sparky-stereo.sources
if compgen -G "/debs/*/*.deb" > /dev/null; then
	# the newer build of each package the image has, and okular: by apt, from the files
	want=()
	for f in /debs/*/*.deb; do
		p=$(dpkg-deb -f "$f" Package)
		case $p in *-dbgsym) continue ;; esac
		if [ -n "$SKIP" ] && [[ $p =~ $SKIP ]]; then continue; fi
		if dpkg-query -W -f="\${Status}" "$p" 2>/dev/null | grep -q "install ok installed" || [ "$p" = okular ] || [ "$p" = okular-data ] \
			|| [ "${p#libokular}" != "$p" ]; then want+=("$f"); fi
	done
	printf "%s\n" "${want[@]}" > /tmp/stage-debs.txt
	apt-get -y --no-install-recommends install "${want[@]}" > /tmp/stage-install.log 2>&1 || { tail -40 /tmp/stage-install.log; exit 1; }
	grep -E "^(Inst|Remv)|^Setting up|^Removing" /tmp/stage-install.log | head -80 || true
	rm -f /etc/apt/sources.list.d/sparky-stereo.sources
fi
useradd --create-home --uid 1000 tester 2>/dev/null || true
dpkg-query -W kwin-wayland okular libqt6widgets6 libqt6waylandclient6 libqt6printsupport6 plasma-wayland-protocols 2>/dev/null || true
'
docker commit "$container" "$NAME" > /dev/null
docker inspect -f '{{.Id}}' "$container" >> "${CIDS:-/dev/null}"
docker rm "$container" > /dev/null
docker image inspect -f '{{.Id}} {{.Architecture}}' "$NAME"
