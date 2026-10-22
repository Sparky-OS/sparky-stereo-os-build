#!/bin/bash
# usage: dev.sh <cmd...>  run in the Qt build container (source ${SPARKY_SCRATCH}/qtgl/src, build ${SPARKY_SCRATCH}/qtgl/build)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
exec docker run --rm --platform linux/amd64 --cpus 4 -u $(id -u):$(id -g) -e HOME=/work/home -e DEBIAN_FRONTEND=noninteractive -v ${SPARKY_SCRATCH:?}/qtgl:/qtgl -v ${SPARKY_SCRATCH:?}/qtgl/work:/work -w /qtgl ${IMG:-qtbase-deb-build:1} "$@"
