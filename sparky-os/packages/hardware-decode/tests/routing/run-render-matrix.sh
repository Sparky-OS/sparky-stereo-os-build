#!/bin/bash
set -euo pipefail
: "${DOCKER_HOST:?Set the granted Docker endpoint}"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
: "${SPARKY_ROUTING_WORK:?Set the owned routing workspace}"
: "${SPARKY_DECODER_WORK:?Set the read-only recorded decoder workspace}"
: "${SPARKY_ROUTING_TESTS:?Set this test directory}"
: "${SPARKY_ROUTING_IMAGE:?Set the qualified container SDK image}"
: "${SPARKY_TEST_PREFIX:?Set an owned container name prefix}"
for pair in ${PAIRS:-amd-only nvidia-only hybrid-amd hybrid-nvidia}; do
 for screens in ${SCREENS:-1 2}; do
  scenario=${RUN_PREFIX:-matrix}-$pair-$screens
  name=${SPARKY_TEST_PREFIX}-$scenario
  device=(); display=amd
  case $pair in amd-only) device=(--device /dev/dri/renderD128 --group-add 125);;
   nvidia-only) device=(--device nvidia.com/gpu=0); display=nvidia;;
   hybrid-*) device=(--device /dev/dri/renderD128 --group-add 125 --device nvidia.com/gpu=0); display=${pair#hybrid-};; esac
  docker run --platform linux/amd64 --cpus 4 --cap-add SYS_NICE --user 1000:1000 --ulimit core=0 "${device[@]}" --name "$name" -e DISPLAY_GPU="$display" -e SCENARIO="$scenario" -e OUTPUT_COUNT="$screens" -e CLIENT_SCRIPT=mpv-clients -v "$SPARKY_ROUTING_WORK:/w" -v "$SPARKY_DECODER_WORK:/prev:ro" -v "$SPARKY_ROUTING_TESTS:/kit:ro" "$SPARKY_ROUTING_IMAGE" sh /kit/kwin-probe.sh
  docker logs "$name" > "$SPARKY_ROUTING_WORK/logs/$scenario-start.log" 2>&1
  echo "$scenario complete"
 done
done
