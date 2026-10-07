#!/bin/bash
# usage: runtest.sh <prog> [args]  runs a test helper in the container against the installed stereo build
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/marble-lane/work:/w -v /K3D/temp/marble-lane/inst:/inst -e QT_QPA_PLATFORM=offscreen marble-build:2 "$@"
