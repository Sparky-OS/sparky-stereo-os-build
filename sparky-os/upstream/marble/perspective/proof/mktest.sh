#!/bin/bash
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v /K3D/temp/marble-lane/work:/w -v /K3D/temp/marble-lane/inst:/inst -v /K3D/temp/marble-lane:/w0 marble-build:1 bash -c '
set -e; cd /w/test
LIBD=$(dirname $(find /inst/stereo -name "libmarblewidget-qt6.so*" | head -1))
S=/w0/marble/src/lib; B=/w0/build-stereo/src/lib/marble
INC="-I$S/marble -I$S/marble/geodata -I$S/marble/geodata/parser -I$S/marble/geodata/handlers -I$S/marble/geodata/handlers/dgml -I$S/marble/geodata/data -I$S/marble/geodata/scene -I$S/marble/graphicsview -I$S/marble/projections -I$S/marble/layers -I$S/astro -I$B -I/w0/build-stereo/src/lib/astro"
g++ -std=c++20 -fPIC -O1 -o ../bin/cameratest cameratest.cpp $INC -I/inst/stereo/include $(pkg-config --cflags Qt6Widgets Qt6Xml) -L$LIBD -lmarblewidget-qt6 $(pkg-config --libs Qt6Widgets Qt6Xml) -Wl,-rpath,$LIBD
g++ -std=c++20 -fPIC -O1 -o ../bin/persptest persptest.cpp $INC -I/inst/stereo/include $(pkg-config --cflags Qt6Widgets Qt6Xml) -L$LIBD -lmarblewidget-qt6 $(pkg-config --libs Qt6Widgets Qt6Xml) -Wl,-rpath,$LIBD
g++ -std=c++20 -fPIC -O1 -o ../bin/probe probe.cpp $INC -I/inst/stereo/include $(pkg-config --cflags Qt6Widgets Qt6Xml) -L$LIBD -lmarblewidget-qt6 $(pkg-config --libs Qt6Widgets Qt6Xml) -Wl,-rpath,$LIBD
echo built'
