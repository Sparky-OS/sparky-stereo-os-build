#!/bin/bash
# Builds the image publish-tree.sh runs Debian's appstream-generator in, tagged with the version the Dockerfile
# pins (sparky-appstream-generator:<version>), which is publish-tree.sh's default SPARKY_APPSTREAM_IMAGE.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=$(sed -n 's/.*appstream-generator=\([^[:space:]]*\).*/\1/p' "$HERE/Dockerfile")
[ -n "$VERSION" ] || { echo "no appstream-generator version pinned in $HERE/Dockerfile" >&2; exit 1; }
exec docker build -t "sparky-appstream-generator:$VERSION" "$@" "$HERE"
