#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -v ${SPARKY_SCRATCH:?}/marble-lane/pkg:/pkg -v ${SPARKY_SCRATCH:?}/marble-lane/work/passwd:/etc/passwd:ro -e HOME=/tmp -e DEB_BUILD_OPTIONS="nocheck parallel=4" marble-build:1 bash -c 'cd /pkg/marble-26.04.0 && dpkg-buildpackage -us -uc -sa 2>&1 | tail -60'
