#!/bin/bash
set -euo pipefail
lane=$(cd "$(dirname "$0")/../.." && pwd)
[ -S "$lane/docker.sock" ] && export DOCKER_HOST="unix://$lane/docker.sock" || true
case_name=${1:-2d}
case "$case_name" in
	2d|alpha-classic-black-2d|alpha-classic-white-2d|alpha-oxygen-black-2d|alpha-oxygen-white-2d|alpha-classic-black-stereo|alpha-classic-white-stereo|alpha-oxygen-black-stereo|alpha-oxygen-white-stereo) ;;
	windows-classic-black-2d|windows-classic-white-2d|windows-oxygen-black-2d|windows-oxygen-white-2d|windows-classic-black-stereo|windows-classic-white-stereo|windows-oxygen-black-stereo|windows-oxygen-white-stereo|gallery-stereo|platform-stereo) ;;
	m2-*|m3-*) ;;
	*) printf 'Unknown probe case: %s\n' "$case_name" >&2; exit 2 ;;
esac
image=${CLASSIC_IMAGE:-classic-look-rig:m1-oxygen}
case "$case_name" in m2-*|m3-*) image=${CLASSIC_IMAGE:-classic-look-rig:m2} ;; esac
container="classic-look-$case_name"
printf '%s\n' "$container" >> "$lane/.artifacts"
trap 'docker stop --timeout 2 "$container" >/dev/null 2>&1 || true; docker rm "$container" >/dev/null 2>&1 || true' EXIT
mkdir -p "$lane/theme/rig/bin"
docker run --name "$container" --platform linux/amd64 --cpus 4 \
	--device /dev/dri/renderD128 --group-add "$(getent group render | cut -d: -f3)" \
	--user "$(id -u):$(id -g)" --entrypoint /bin/sh \
	-v "$lane:$lane" -e CLASSIC_LANE="$lane" -e CLASSIC_CASE="$case_name" \
	-e CLASSIC_GTK4_ENV="${CLASSIC_GTK4_ENV:-X=1}" -e CLASSIC_GTK3_ENV="${CLASSIC_GTK3_ENV:-X=1}" -e CLASSIC_SCENE="${CLASSIC_SCENE:-}" -e CLASSIC_AUDIT="${CLASSIC_AUDIT:-}" -e CLASSIC_EFFECT="${CLASSIC_EFFECT:-magiclamp}" -e CLASSIC_ANIM="${CLASSIC_ANIM:-1}" -e CLASSIC_KVANTUM="${CLASSIC_KVANTUM:-KubabbarGlass}" \
	-v /usr/share/plasma/desktoptheme/oxygen:/usr/share/plasma/desktoptheme/oxygen:ro \
	"$image" -c '
	set -e
	# Copying removes file capabilities unavailable in this unprivileged fixture.
	if [ ! -f "$CLASSIC_LANE/theme/rig/bin/kwin_wayland" ]; then
		cp /usr/bin/kwin_wayland "$CLASSIC_LANE/theme/rig/bin/kwin_wayland"
	fi
	if [ -n "${CLASSIC_AUDIT:-}" ] && [ ! -f "$CLASSIC_LANE/theme/rig/bin/style-audit.so" ]; then
		g++ -shared -fPIC -o "$CLASSIC_LANE/theme/rig/bin/style-audit.so" "$CLASSIC_LANE/theme/rig/m2/style-audit.cpp" $(pkg-config --cflags --libs Qt6Widgets) -ldl
	fi
	dbus-run-session -- python3 "$CLASSIC_LANE/theme/rig/probe.py" \
		> "$CLASSIC_LANE/theme/evidence/probe-$CLASSIC_CASE.log" 2>&1
	'
