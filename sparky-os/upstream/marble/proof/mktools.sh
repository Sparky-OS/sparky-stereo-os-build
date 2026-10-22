#!/bin/bash
# builds the test helpers inside the container
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v ${SPARKY_SCRATCH:?}/marble-lane/work:/w marble-build:1 bash -c '
set -e; cd /w
g++ -fPIC -O1 -o bin/capture capture.cpp $(pkg-config --cflags --libs Qt6Gui Qt6DBus)
gcc -O1 -o bin/fakeinput fakeinput.c fake-input-protocol.c -I. $(pkg-config --cflags --libs wayland-client)
ls -la bin'
