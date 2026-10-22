#!/bin/bash
# usage: [IMG=plank-run:A] rp.sh <name> <clip file> [steps-json]    (env PBIN, PEXTRA, SCREEN passed through)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
W=${SPARKY_WORKSPACES:?}/plank-player
P=${SPARKY_WORKSPACES:?}/players-stereo/.scratch/run
name=$1; shift
rm -rf $W/out/$name
exec docker run --rm --name plank-$name --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 \
  -e HOME=/tmp/home -e LIBGL_ALWAYS_SOFTWARE=${SW:-0} -e SCREEN -e PBIN -e PEXTRA -e DEBIAN_FRONTEND=noninteractive \
  -v $P/passwd:/etc/passwd:ro -v $W:/w -v $P:/p:ro ${IMG:-plank-run:A} \
  dbus-run-session -- python3 /w/run/driver.py /w/out/$name "$@"
