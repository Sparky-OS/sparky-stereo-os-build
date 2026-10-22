#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Runs ./bench inside the tool image (Dockerfile), as the current user, with KVM if the host has it.
#
#   ./run-in-docker.sh [-m HOSTDIR:CONTAINERDIR]... bench-arguments...
#
# The image is built on first use. The directory of this script is mounted at /bench (read-only) and ./bench-work at /work. Mount your
# kernel tree and its build directory at the same path they were built at (kbuild records absolute paths), e.g.
#   ./run-in-docker.sh -m /src/linux:/src/linux:ro -m /src/build:/src/build:ro \
#       --kernel /src/build/arch/x86/boot/bzImage --ksrc /src/build run policy hibernate
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=${BENCH_IMAGE:-hibernate-bench:2}
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build --platform linux/amd64 -t "$IMAGE" "$HERE"
mkdir -p "$PWD/bench-work"
MOUNTS=
while [ "${1:-}" = "-m" ]; do MOUNTS="$MOUNTS -v $2"; shift 2; done
KVM=
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then KVM="--device /dev/kvm --group-add $(getent group kvm | cut -d: -f3)"; fi
# shellcheck disable=SC2086
exec docker run --rm --platform linux/amd64 --cpus "${BENCH_CPUS:-4}" --memory "${BENCH_MEM:-16g}" --user "$(id -u):$(id -g)" $KVM \
    -v "$HERE":/bench:ro -v "$PWD/bench-work":/work $MOUNTS -e HOME=/tmp "$IMAGE" /bench/bench --work /work "$@"
