#!/bin/bash
# run a command in the qtbase build image as the invoking user, /K3D/temp/qtbase-pkg mounted at /work
exec docker run --rm --platform linux/amd64 --cpus 4 --user $(id -u):$(id -g) -e HOME=/work/home -e DEBIAN_FRONTEND=noninteractive -v /K3D/temp/qtbase-pkg:/work -w /work ${IMG:-qtbase-deb-build:1} "$@"
