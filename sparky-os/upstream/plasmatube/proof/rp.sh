#!/bin/bash
# usage: [IMG=pt-run:A] rp.sh <name> <video id> [steps-json]    (env PTBIN, PTEXTRA, VIDEOS passed through)
W=/K3D/temp/partners/queue/plasmatube
P=/K3D/temp/partners/queue/players-stereo/.scratch/run
name=$1; shift
rm -rf $W/out/$name
exec docker run --rm --name ptr-$name --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 \
  -e HOME=/tmp/home -e LIBGL_ALWAYS_SOFTWARE=${SW:-0} -e SCREEN -e PTBIN -e PTEXTRA -e VIDEOS -e DEBIAN_FRONTEND=noninteractive \
  -v $P/passwd:/etc/passwd:ro -v $W:/w -v $P:/p:ro ${IMG:-pt-run:A} \
  dbus-run-session -- python3 /w/run/driver.py /w/out/$name "$@"
