#!/bin/bash
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/marble-lane/work:/w -v /K3D/temp/marble-lane:/w0 marble-pkg:1 bash -c '
set -e; cd /w/test
S=/w0/marble/src/lib
INC="-I/usr/include/marble -I$S/marble -I$S/marble/geodata -I$S/marble/geodata/parser -I$S/marble/geodata/handlers -I$S/marble/geodata/handlers/dgml -I$S/marble/geodata/data -I$S/marble/geodata/scene -I$S/marble/graphicsview -I$S/marble/projections -I$S/marble/layers -I$S/astro -I/usr/include/astro"
g++ -std=c++20 -fPIC -O1 -o ../bin/probe-pkg probe.cpp $INC $(pkg-config --cflags Qt6Widgets Qt6Xml) -lmarblewidget-qt6 $(pkg-config --libs Qt6Widgets Qt6Xml)
ldd ../bin/probe-pkg | grep marble; echo built'
