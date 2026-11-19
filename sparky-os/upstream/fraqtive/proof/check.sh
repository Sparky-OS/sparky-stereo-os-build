#!/bin/sh
# check.sh IMAGE [ROUTE...]: Fraqtive's 3D view in a throwaway Stereo KWin (virtual output) on each route, 0 when it draws on all.
# IMAGE holds the edition's or Debian's packages and fraqtive (docker, as the stereo-proof-rig skill says); it needs a render
# node for KWin: RENDER_ARGS="--device /dev/dri/renderD128 --group-add GID" (or --device nvidia.com/gpu=0). ROUTE is wayland or xcb.
# WORK holds the files of this folder, copied beside a passwd and group file naming uid 1000 and capture.py, fakeinput
# (stereo-proof-rig scripts, built with build-fakeinput.sh) under skill/ and bin/. Red on Debian's fraqtive 0.4.8.1-1, green on 0.4.8.1-1+stereo3d1.
set -eu
img=$1; shift
[ $# -gt 0 ] || set -- wayland xcb
: "${WORK:?folder with cell.sh, skill/capture.py, bin/fakeinput, passwd, group}"
: "${OUT:?folder for the captures}"
mkdir -p "$OUT"
status=0
for route in "$@"; do
	name=check-$route
	mkdir -p "$OUT/$name"
	docker run --rm --pull=never --ulimit core=0 --cpus 4 --user 1000:1000 --cap-add SYS_NICE ${RENDER_ARGS:?} \
		--mount type=bind,src="$WORK/passwd",dst=/etc/passwd,readonly --mount type=bind,src="$WORK/group",dst=/etc/group,readonly \
		--mount type=bind,src="$WORK",dst=/w,readonly --mount type=bind,src="$OUT/$name",dst=/o --tmpfs /tmp:exec,mode=1777 \
		"$img" dbus-run-session -- /w/cell.sh "$route" "/o/$name" >/dev/null 2>&1 || true
	python3 -I "$(dirname "$0")/measure.py" --assert "$OUT/$name/$name-3d.png" || status=1
done
exit $status
