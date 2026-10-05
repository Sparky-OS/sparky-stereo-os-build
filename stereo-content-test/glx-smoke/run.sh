#!/bin/sh
# usage: run.sh software|gpu [directory of Mesa .deb files to install over the image's]
# Mono and stereo glxgears under a headless KWin with Xwayland: for each, the X window's
# size and whether it carries the stereo declaration. "software" runs the client on
# llvmpipe, "gpu" through the GPU driver of /dev/dri/renderD128 (the test user joins the
# device's group). Expected with our Mesa: mono 300x300 undeclared; stereo declared 3 and
# held by KWin in a 600x300 X window, on both paths.
set -eu
mode=$1; debs=${2:-}
here=$(dirname "$(readlink -f "$0")")
gid=$(stat -c %g /dev/dri/renderD128)
exec docker run --rm --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add "$gid" \
	-e SMOKE_MODE="$mode" -e SMOKE_GID="$gid" ${debs:+-v "$debs":/debs:ro} \
	-v "$here":/w:ro "${SMOKE_IMAGE:-qt-stereo-run:latest}" /w/outer.sh
