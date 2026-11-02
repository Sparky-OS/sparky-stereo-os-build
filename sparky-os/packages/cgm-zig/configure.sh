#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/source.env"
SOURCE=${1:?Usage: configure.sh SOURCE EMPTY_BUILD_DIRECTORY}
BUILD=${2:?Usage: configure.sh SOURCE EMPTY_BUILD_DIRECTORY}
test "$(dpkg --print-architecture)" = amd64
test "$(git -C "$SOURCE" rev-parse HEAD)" = "$CGM_ZIG_COMMIT"
if [ -e "$BUILD" ] || [ -L "$BUILD" ]; then
	printf 'cgm-zig: configure requires a fresh build directory: %s\n' "$BUILD" >&2
	exit 1
fi
cmake -S "$SOURCE" -B "$BUILD" -G Ninja \
	-DCMAKE_BUILD_TYPE=RelWithDebInfo \
	-DCMAKE_PREFIX_PATH=/usr/lib/llvm-21 \
	-DCMAKE_C_COMPILER=clang-21 -DCMAKE_CXX_COMPILER=clang++-21 \
	-DZIG_VERSION="$CGM_ZIG_VERSION" \
	-DZIG_RELEASE_SAFE=ON -DZIG_STATIC_LLVM=OFF \
	-DZIG_TARGET_MCPU=baseline \
	'-DZIG_EXTRA_BUILD_ARGS=-Ddebug-extensions;-j4'
ninja -C "$BUILD" -t commands stage3 > "$BUILD/stage3-commands.txt"
python3 "$HERE/check-stage3-command.py" "$BUILD/stage3-commands.txt"
