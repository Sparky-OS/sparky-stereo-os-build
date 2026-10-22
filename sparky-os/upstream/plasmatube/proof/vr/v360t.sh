#!/bin/bash
# usage: v360t.sh <clip> <vf> [mpv args]: first frame as PNG into vr/out
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
c=$1; vf=$2; shift 2
rm -rf ${SPARKY_WORKSPACES:?}/plasmatube/vr/out; mkdir -p ${SPARKY_WORKSPACES:?}/plasmatube/vr/out
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v ${SPARKY_WORKSPACES:?}/plasmatube/vr:/v pt-run:B mpv --no-config --ao=null --vo=image --vo-image-outdir=/v/out --frames=2 --msg-level=all=info "$@" --vf="$vf" /v/clips/$c 2>&1 | grep -v pw.conf | tail -8
