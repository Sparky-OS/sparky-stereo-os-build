#!/bin/bash
# Milestone 2 checks that need no compositor: run after the capture cases (see evidence/commands.txt) and after tools/icons3d renders.
# Needs the fixture image with Blender and numpy (classic-look-blender) so the icon checks can read the 16-bit renders.
set -euo pipefail
lane=$(cd "$(dirname "$0")/../../.." && pwd)
[ -S "$lane/docker.sock" ] && export DOCKER_HOST="unix://$lane/docker.sock" || true
container=classic-look-verify-m2
printf '%s\n' "$container" >> "$lane/.artifacts"
trap 'docker rm "$container" >/dev/null 2>&1 || true' EXIT
docker run --name "$container" --platform linux/amd64 --cpus 2 --user "$(id -u):$(id -g)" --entrypoint /bin/sh \
	-v "$lane:$lane" -w "$lane/theme" "${CLASSIC_IMAGE:-classic-look-blender}" -c '
	set -e
	export LANG=C.UTF-8
	python3 tools/validate_assets.py > evidence/verify-validate_assets.log
	python3 tools/check_buttons.py > evidence/m2/buttons-check.log
	python3 tools/check_cursors.py > evidence/m2/cursors-check.log
	python3 tools/check_helpers.py > evidence/m2/helpers-check.log
	python3 tools/check_gtk.py > evidence/m2/gtk-check.log
	python3 tools/icons3d/check_icons.py evidence/m2/icons3d evidence/m2/icons3d-check.json > evidence/m2/icons3d-check.log
	python3 tools/icons3d/check_calibration.py evidence/m2/icons3d 256 evidence/m2/calibration-check.json > evidence/m2/calibration-check.log
	bash rig/m2/one-click.sh 2>&1 | grep -v "xrdb\|xcb_connect" > evidence/m2/one-click.log
	grep -q "widgetStyle = Breeze" evidence/m2/one-click.log
	grep -q "gtk-theme=Kubabbar-Glass" evidence/m2/one-click.log
	echo "all milestone 2 checks passed"
	'
