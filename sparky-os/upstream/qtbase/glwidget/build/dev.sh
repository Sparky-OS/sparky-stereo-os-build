#!/bin/bash
# usage: dev.sh <cmd...>  run in the Qt build container (source /K3D/temp/qtgl/src, build /K3D/temp/qtgl/build)
exec docker run --rm --platform linux/amd64 --cpus 4 -u $(id -u):$(id -g) -e HOME=/work/home -e DEBIAN_FRONTEND=noninteractive -v /K3D/temp/qtgl:/qtgl -v /K3D/temp/qtgl/work:/work -w /qtgl ${IMG:-qtbase-deb-build:1} "$@"
