#!/bin/sh
# Builds nvkms-query (static) in a debian:testing container, against the
# headers of the open GPU kernel modules tree.
# Usage: build.sh [open-gpu-kernel-modules-dir] [output]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${1:-/K3D/temp/partners/queue/nvidia-16bpc/open-gpu-kernel-modules}
OUT=${2:-/K3D/temp/sparky-os/nvkms-query}
VER=$(sed -n 's/^NVIDIA_VERSION *= *//p' "$TREE/version.mk")
mkdir -p "$(dirname "$OUT")"
docker run --rm --cpus 4 -e DEBIAN_FRONTEND=noninteractive \
	-v "$HERE":/src:ro -v "$TREE":/tree:ro -v "$(dirname "$OUT")":/out \
	debian:testing sh -c "
set -e
apt-get update -qq && apt-get -y install --no-install-recommends gcc libc6-dev >/dev/null
S=/tree/src
gcc -O2 -Wall -static -DNVKMS_DRIVER_VERSION=\\\"$VER\\\" \
  -I\$S/nvidia-modeset/interface -I\$S/common/sdk/nvidia/inc -I\$S/common/inc \
  -I\$S/common/unix/common/inc -I\$S/common/unix/common/utils/interface \
  -o /out/$(basename "$OUT") /src/nvkms-query.c
"
echo "built $OUT (driver version $VER)"
