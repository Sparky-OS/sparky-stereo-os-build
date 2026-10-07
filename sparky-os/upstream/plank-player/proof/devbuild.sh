#!/bin/bash
# dev build of the working tree in plank-build:1 into /w/dev-build, installed into /w/dev-prefix
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) --cpus 4 -e HOME=/tmp/h -v /K3D/temp/partners/queue/plank-player:/w plank-build:1 bash -c '
set -e
mkdir -p /w/dev-build && cd /w/dev-build
cmake -S /w/tree/plank-player -B . -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/w/dev-prefix -DCMAKE_CXX_FLAGS="-Wall -Wextra" > cmake.log 2>&1 || { tail -30 cmake.log; exit 1; }
grep -E "HAVE_STEREO|Stereo" cmake.log
make -j4 2>&1 | grep -E "warning|error|Error" | head -30
make install > /dev/null 2>&1; ls /w/dev-prefix/bin'
