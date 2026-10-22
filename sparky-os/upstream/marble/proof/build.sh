#!/bin/bash
# usage: build.sh [make-target]   builds the Marble tree in the container, installs to /inst/stereo
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
T=${1:-install}
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -v ${SPARKY_SCRATCH:?}/marble-lane:/w0 -v ${SPARKY_SCRATCH:?}/marble-lane/inst:/inst -v ${SPARKY_SCRATCH:?}/marble-lane/work/passwd:/etc/passwd:ro -e HOME=/tmp marble-build:1 bash -c "
set -e
mkdir -p /w0/build-stereo && cd /w0/build-stereo
[ -f CMakeCache.txt ] || cmake -S /w0/marble -B . -G 'Unix Makefiles' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/inst/stereo -DBUILD_QT_AND_KDE=ON -DBUILD_TESTING=OFF -DBUILD_TOUCH=OFF -DWITH_DESIGNER_PLUGIN=OFF -DBUILD_MARBLE_TESTS=OFF
make -j4 $T
"
