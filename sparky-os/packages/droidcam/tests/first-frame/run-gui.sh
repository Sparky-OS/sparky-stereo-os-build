#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/24
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: gui-cases.sh in a container with a virtual display and no network (nothing reaches the person's desktop).
# Usage: DOCKER_HOST=... IMAGE=an-image-with-xvfb-xdotool-imagemagick-gcc-python3-and-gtk run-gui.sh staged|first|fixed GUI OUTDIR
set -euo pipefail
MODE=${1:?staged, first or fixed} GUI=$(realpath "${2:?path of droidcam (the window program)}") OUT=$(realpath -m "${3:?output folder}")
IMAGE=${IMAGE:?an image with Xvfb, xdotool, ImageMagick, gcc, python3 and the libraries of the window program}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
docker run --rm --network none --cpus 2 --ulimit core=1 ${CONTAINER_NAME:+--name "$CONTAINER_NAME"} \
	-v "$HERE":"$HERE":ro -v "$(dirname "$GUI")":"$(dirname "$GUI")":ro -v "$OUT":"$OUT" "$IMAGE" bash -c '
mknod /dev/video0 c 1 3 && chmod 666 /dev/video0 && chown "$1:$2" "$6" &&
exec setpriv --reuid="$1" --regid="$2" --clear-groups bash "$3/gui-cases.sh" "$4" "$5" "$6"' _ "$(id -u)" "$(id -g)" "$HERE" "$MODE" "$GUI" "$OUT"
