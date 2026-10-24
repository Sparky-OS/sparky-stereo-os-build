#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Run in the matching Qt package image, never during the A10 measurement.
set -euo pipefail
cd -- "$(dirname -- "$0")"
output=${1:?output shared-library path}
c++ -shared -fPIC -O2 -std=c++17 observer.cpp -o "$output" \
 $(pkg-config --cflags --libs Qt6Multimedia Qt6Core egl gl) -ldl
