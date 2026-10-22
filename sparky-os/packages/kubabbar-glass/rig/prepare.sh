#!/bin/bash
# Rebuild the headless fixture from the pinned, already available Stereo KWin image.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
lane=$(cd "$(dirname "$0")/../.." && pwd)
[ -S "$lane/docker.sock" ] && export DOCKER_HOST="unix://$lane/docker.sock" || true
task_uid=$(id -u)
task_gid=$(id -g)
base=sha256:6beb617f6a0f17e7db18b2bce41fd46111e112124583d8847966e545f5d1f9e6
printf '%s\n' classic-look-prepare classic-look-rig:m1-oxygen >> "$lane/.artifacts"
trap 'docker rm -f classic-look-prepare >/dev/null 2>&1 || true' EXIT
docker run --name classic-look-prepare --platform linux/amd64 --cpus 4 --user 0:0 \
	--entrypoint /bin/sh \
	-v ${SPARKY_REPO_DIR:?}:/var/local/sparky-stereo-repo:ro \
	-e CLASSIC_UID="$task_uid" -e CLASSIC_GID="$task_gid" "$base" -c '
	set -e
	apt-get update
	DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
		plasma-workspace plasma-desktop kwin-style-aurorae konsole kate systemsettings \
		python3-pyside6.qtwidgets python3-pyside6.qtsvg python3-pyside6.qtquick python3-dbus python3-gi librsvg2-bin xvfb xauth \
		dbus-x11 gtk-3-examples fonts-dejavu-core oxygen-icon-theme \
		kde-style-oxygen-qt6 kwin-decoration-oxygen plasma-theme-oxygen
	groupadd -g "$CLASSIC_GID" classic
	useradd -u "$CLASSIC_UID" -g "$CLASSIC_GID" -M -d /nonexistent classic
	rm -rf /var/lib/apt/lists/*
	'
docker logs classic-look-prepare > "$lane/theme/evidence/rig-prepare.log" 2>&1
docker commit classic-look-prepare classic-look-rig:m1-oxygen
