#!/bin/bash
# usage: v360t.sh <clip> <vf> [mpv args]: first frame as PNG into vr/out
c=$1; vf=$2; shift 2
rm -rf /K3D/temp/partners/queue/plasmatube/vr/out; mkdir -p /K3D/temp/partners/queue/plasmatube/vr/out
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/partners/queue/plasmatube/vr:/v pt-run:B mpv --no-config --ao=null --vo=image --vo-image-outdir=/v/out --frames=2 --msg-level=all=info "$@" --vf="$vf" /v/clips/$c 2>&1 | grep -v pw.conf | tail -8
