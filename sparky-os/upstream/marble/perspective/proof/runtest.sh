#!/bin/bash
# usage: runtest.sh <prog> [args]  runs a test helper in the container against the installed stereo build
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v ${SPARKY_SCRATCH:?}/marble-lane/work:/w -v ${SPARKY_SCRATCH:?}/marble-lane/inst:/inst -e QT_QPA_PLATFORM=offscreen marble-build:2 "$@"
