#!/bin/bash
# usage: kdrun.sh <outdir-name> [env VAR=val ...]   runs krita-wl.sh in the dev image (prefix p3) or IMG
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
d=${SPARKY_SCRATCH:?}/krita-p3c/ev/$1; shift
mkdir -p $d
exec docker run --rm --platform linux/amd64 --cpus 4 --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 -u $(id -u):$(id -g) \
  -e OUT=/ev/run -e SSH_ASKPASS_REQUIRE=never "$@" \
  -v ${SPARKY_WORKSPACES:?}/krita-stereo/img/passwd:/etc/passwd:ro -v ${SPARKY_SCRATCH:?}/krita-p3c:/k -v $d:/ev -v ${SPARKY_WORKSPACES:?}/krita-stereo:/w -v ${HOME}/krita-p3c-work:/b \
  ${IMG:-krita-p3-proof:s3} /k/rig/krita-wl.sh
