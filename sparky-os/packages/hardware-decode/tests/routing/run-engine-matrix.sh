#!/bin/bash
set -euo pipefail
: "${DOCKER_HOST:?Set the granted Docker endpoint}"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY
: "${SPARKY_ROUTING_WORK:?Set the owned routing workspace}"
: "${SPARKY_DECODER_WORK:?Set the read-only recorded decoder workspace}"
: "${SPARKY_ROUTING_TESTS:?Set this test directory}"
: "${SPARKY_ROUTING_IMAGE:?Set the qualified container SDK image}"
: "${SPARKY_TEST_PREFIX:?Set an owned container name prefix}"
for pair in amd-only nvidia-only hybrid-amd hybrid-nvidia; do
 device=(); display=amd; extra=()
 case $pair in amd-only) device=(--device /dev/dri/renderD128 --group-add 125); extra=(-e ONLY_AMD=1);;
  nvidia-only) device=(--device nvidia.com/gpu=0); display=nvidia;;
  hybrid-*) device=(--device /dev/dri/renderD128 --group-add 125 --device nvidia.com/gpu=0); display=${pair#hybrid-};; esac
 for client in choice-clients caps-clients engine-clients vlc-clients; do
  scenario=final-$client-$pair
  name=${SPARKY_TEST_PREFIX}-$scenario
  docker run --platform linux/amd64 --cpus 4 --user 1000:1000 --ulimit core=0 "${device[@]}" "${extra[@]}" --name "$name" -e HOME=/tmp/home -e DISPLAY_GPU="$display" -e SCENARIO="$scenario" -e CLIENT_SCRIPT="$client" -v "$SPARKY_ROUTING_WORK:/w" -v "$SPARKY_DECODER_WORK:/prev:ro" -v "$SPARKY_ROUTING_WORK/vlc-build/modules/.libs/libavcodec_plugin.so:/usr/lib/x86_64-linux-gnu/vlc-stereo/vlc/plugins/codec/libavcodec_plugin.so:ro" -v "$SPARKY_ROUTING_TESTS:/kit:ro" "$SPARKY_ROUTING_IMAGE" sh /kit/baseline-weston.sh
  docker logs "$name" > "$SPARKY_ROUTING_WORK/logs/$scenario-start.log" 2>&1
  echo "$scenario finished"
 done
done
