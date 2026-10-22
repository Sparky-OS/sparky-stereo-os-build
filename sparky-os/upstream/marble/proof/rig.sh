#!/bin/bash
# usage: rig.sh <name> <clients-json> <steps-json>   (env IMG, SCREEN, MOUNTS)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
W=${SPARKY_SCRATCH:?}/marble-lane/work
name=$1
docker run --rm --platform linux/amd64 --name marble-rig-$name --user $(id -u):$(id -g) --cpus 4 --cap-add SYS_NICE \
  --device /dev/dri/renderD128 --group-add 125 -e HOME=/tmp/home -e SCREEN -e DEBIAN_FRONTEND=noninteractive \
  -v $W/passwd:/etc/passwd:ro -v ${SPARKY_SCRATCH:?}/marble-lane:/w0 -v $W:/w -v ${SPARKY_SCRATCH:?}/marble-lane/inst:/inst $MOUNTS ${IMG:-marble-build:1} \
  dbus-run-session -- python3 /w/rig.py /w/out/$name "$2" "$3"
