#!/bin/bash
# like dev.sh with the render node (for tests that need EGL)
exec docker run --rm --platform linux/amd64 --cpus 4 --device /dev/dri/renderD128 --group-add 125 -u $(id -u):$(id -g) -e HOME=/work/home -e DEBIAN_FRONTEND=noninteractive -v /K3D/temp/qtgl:/qtgl -v /K3D/temp/qtgl/work:/work -w /qtgl ${IMG:-qtbase-deb-build:1} "$@"
