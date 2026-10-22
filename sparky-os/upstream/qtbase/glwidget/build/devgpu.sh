#!/bin/bash
# like dev.sh with the render node (for tests that need EGL)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
exec docker run --rm --platform linux/amd64 --cpus 4 --device /dev/dri/renderD128 --group-add 125 -u $(id -u):$(id -g) -e HOME=/work/home -e DEBIAN_FRONTEND=noninteractive -v ${SPARKY_SCRATCH:?}/qtgl:/qtgl -v ${SPARKY_SCRATCH:?}/qtgl/work:/work -w /qtgl ${IMG:-qtbase-deb-build:1} "$@"
