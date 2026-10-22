#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
exec docker run --rm --platform linux/amd64 --cpus 4 --user $(id -u):$(id -g) -e HOME=/work/home -e DEBIAN_FRONTEND=noninteractive -v ${SPARKY_SCRATCH:?}/qtbase-csd/work:/work -w /work ${IMG:-qtbase-deb-build:1} "$@"
