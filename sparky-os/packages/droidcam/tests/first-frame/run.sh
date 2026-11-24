#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/24
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the replay without a phone (see cases.sh), in a container with no network. The client's libraries come from the image.
# Usage: DOCKER_HOST=... IMAGE=an-image-with-gcc-python3-and-the-clients-libraries run.sh staged|first|fixed CLIENT
set -euo pipefail
MODE=${1:?staged, first or fixed} CLIENT=$(realpath "${2:?path of droidcam-cli}")
IMAGE=${IMAGE:?an image with gcc, python3 and the libraries droidcam-cli needs}
HERE=$(cd "$(dirname "$0")" && pwd)
docker run --rm --network none --cpus 2 --ulimit core=1 --user "$(id -u):$(id -g)" -v "$HERE":"$HERE":ro -v "$(dirname "$CLIENT")":"$(dirname "$CLIENT")":ro \
	${CONTAINER_NAME:+--name "$CONTAINER_NAME"} "$IMAGE" bash "$HERE/cases.sh" "$MODE" "$CLIENT"
