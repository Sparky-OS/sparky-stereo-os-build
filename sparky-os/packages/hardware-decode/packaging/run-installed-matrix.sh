#!/bin/bash
# Copyright 2026 Daniel Campos Ramos; GPL-3.0-or-later.
set -euo pipefail
: "${DOCKER_HOST:?Set the granted Docker endpoint}"
: "${SPARKY_INSTALLED_WORK:?Set the owned installed-package workspace}"
: "${SPARKY_DECODER_WORK:?Set the read-only source fixture/reference directory}"
: "${SPARKY_ROUTING_TESTS:?Set the hardware-decode/tests/routing directory}"
: "${SPARKY_INSTALLED_IMAGE:?Set the installed-package image}"
: "${SPARKY_TEST_PREFIX:?Set an owned container prefix}"
: "${SPARKY_ARTIFACTS:?Set the lane artifact record}"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
for pair in amd-only nvidia-only hybrid-amd hybrid-nvidia; do
 device=(); display=amd; extra=()
 case $pair in
 amd-only) device=(--device /dev/dri/renderD128 --group-add 125); extra=(-e ONLY_AMD=1);;
 nvidia-only) device=(--device nvidia.com/gpu=0); display=nvidia;;
 hybrid-*) device=(--device /dev/dri/renderD128 --group-add 125 --device nvidia.com/gpu=0); display=${pair#hybrid-};;
 esac
 for client in choice-clients caps-clients engine-clients vlc-clients; do
  scenario=final-$client-$pair
  name=$SPARKY_TEST_PREFIX-$scenario
  printf '%s\n' "$name" >> "$SPARKY_ARTIFACTS"
  docker run --platform linux/amd64 --cpus 4 --user 1000:1000 --ulimit core=0 "${device[@]}" "${extra[@]}" --name "$name" \
   -e HOME=/tmp/home -e ROUTE_INSTALLED=1 -e DISPLAY_GPU="$display" -e SCENARIO="$scenario" -e CLIENT_SCRIPT="$client" \
   -v "$SPARKY_INSTALLED_WORK:/w" -v "$SPARKY_DECODER_WORK:/prev:ro" -v "$SPARKY_ROUTING_TESTS:/kit:ro" \
   "$SPARKY_INSTALLED_IMAGE" sh /kit/baseline-weston.sh
  docker logs "$name" > "$SPARKY_INSTALLED_WORK/logs/$scenario-container.log" 2>&1
 done
done
