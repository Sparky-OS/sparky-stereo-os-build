#!/bin/bash
exec docker run --rm --platform linux/amd64 --cpus 4 --user $(id -u):$(id -g) -e HOME=/work/home -e DEBIAN_FRONTEND=noninteractive -v /K3D/temp/qtbase-alpha/work:/work -w /work ${IMG:-qtbase-deb-build:1} "$@"
