#!/bin/bash
# builds the test helpers inside the container
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/marble-lane/work:/w marble-build:1 bash -c '
set -e; cd /w
g++ -fPIC -O1 -o bin/capture capture.cpp $(pkg-config --cflags --libs Qt6Gui Qt6DBus)
gcc -O1 -o bin/fakeinput fakeinput.c fake-input-protocol.c -I. $(pkg-config --cflags --libs wayland-client)
ls -la bin'
