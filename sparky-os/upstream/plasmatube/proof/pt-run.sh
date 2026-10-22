#!/bin/bash
# usage: pt-run.sh <before|after> <clip file> <out name> [resolution]: PeerTube's transcode of a clip with the original or the patched ffmpeg package
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
d=dist; [ "$1" = before ] && d=dist-orig
run=${SPARKY_WORKSPACES:?}/plasmatube/run
$run/node.sh "cd /pt && FFDIST=$d FORCE_VIDEO=$FORCE_VIDEO node /pt/.pt-transcode.mjs /pt /w/clips/$2 /w/pt-ff/$3-$1.mp4 $4 2>&1 | tail -4"
