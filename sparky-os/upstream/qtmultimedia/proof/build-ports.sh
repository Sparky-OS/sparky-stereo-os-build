#!/bin/bash
# dev builds of Dragon Player and Plank Player (QML changes only) into /w/dragon-prefix and /w/plank-prefix
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/w/home -v /K3D/temp/qtmm-lane:/w -v /K3D/temp/partners/queue/plank-player/tree/plank-player:/src-plank:ro qtmm-build:2 bash -c '
set -e
mkdir -p /w/dragon-build && cd /w/dragon-build && cmake -S /w/dragon/dragon-26.04.0 -B . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/w/dragon-prefix -DBUILD_TESTING=OFF > cmake.log 2>&1 || { tail -20 cmake.log; exit 1; }
make -j4 > make.log 2>&1 || { tail -30 make.log; exit 1; }
make install > /dev/null 2>&1
mkdir -p /w/plank-build && cd /w/plank-build && cmake -S /src-plank -B . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/w/plank-prefix > cmake.log 2>&1 || { tail -20 cmake.log; exit 1; }
make -j4 > make.log 2>&1 || { tail -30 make.log; exit 1; }
make install > /dev/null 2>&1
find /w/dragon-prefix /w/plank-prefix -type f | head -30
'
