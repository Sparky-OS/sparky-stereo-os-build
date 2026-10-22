#!/bin/bash
# usage: kdrun.sh <name> [-e VAR=val ...]   (IMG=image)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
K=${SPARKY_SCRATCH:?}/krita-alpha/k; d=${SPARKY_SCRATCH:?}/krita-alpha/ev/$1; shift
rm -rf $d; mkdir -p $d
exec docker run --rm --platform linux/amd64 --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 -u $(id -u):$(id -g) \
  -e OUT=/ev/run -e SSH_ASKPASS_REQUIRE=never "$@" \
  -v ${SPARKY_WORKSPACES:?}/krita-stereo/img/passwd:/etc/passwd:ro -v $K:/k -v $d:/ev ${IMG:-krita-p3d-proof:s6} /k/rig/krita-wl.sh
