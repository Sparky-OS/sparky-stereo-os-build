#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# The proof of ORDER 51, one fresh session per case: runs run-proof.sh in an image with no network at all.
# Usage: proof.sh IMAGE OUTDIR SKILL_SCRIPTS ENABLE   (IMAGE the -red or -green image of rig-image.sh; SKILL_SCRIPTS the stereo-proof-rig scripts folder)
set -euo pipefail
STEPS=${5:-steps-preview.txt}
IMAGE=${1:?image} OUT=$(realpath -m "${2:?output folder}") SK=$(realpath "${3:?stereo-proof-rig scripts}") ENABLE=${4:-1}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT" && chmod 777 "$OUT"
docker run --ulimit core=1 --pull=never --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}katemark-proof-$ENABLE-$$" \
	--network none --platform linux/amd64 --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add "${RENDER_GID:-125}" --user "$(id -u):$(id -g)" \
	-v "$OUT":/out -v "$HERE":/proof:ro -v "$SK":/skill:ro \
	"$IMAGE" bash /proof/run-proof.sh /out/run /skill /proof/fixtures/proof.md "$ENABLE" "/proof/$STEPS"
