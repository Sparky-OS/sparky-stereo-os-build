#!/bin/bash
# usage: probe.sh <clip> [mpv args]: the video's parameters before (video-params) and after (video-out-params) the filters
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
c=$1; shift
docker run --rm --platform linux/amd64 -v ${SPARKY_WORKSPACES:?}/plasmatube/clips:/c:ro -v ${SPARKY_WORKSPACES:?}/plasmatube/pt-ff:/o:ro ${IMG:-pt-run:A} mpv --no-config --vo=null --ao=null --no-audio --frames=60 --msg-level=all=no,statusline=status "$@" --term-status-msg='in=${video-params/stereo-in} dw=${video-params/dw} dh=${video-params/dh} | out=${video-out-params/stereo-in} outdw=${video-out-params/dw} outdh=${video-out-params/dh}' /o/$c 2>&1 | tr '\r' '\n' | grep 'in=' | tail -1
