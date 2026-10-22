#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Proves the kernel configuration of the flavours without building a kernel: in the build image, on a scratch copy of the
# pinned upstream tag with the patch series applied, runs kernel/configure.sh in O= mode and prints, per flavour, the table of
# the fragment's options (wanted, Debian's value, value after Debian + olddefconfig on the patched tree, final value, the reason),
# the options that changed without being named, and Debian options that are gone from the tree. Exit status 1 if an option of
# the fragments does not hold.
#
#   kernel/tests/config-proof.sh [out-dir] [flavour...]     (default ${SPARKY_SCRATCH}/linux-stereo3d-config-proof, base v3 rt)
#
# Uses the same environment as build-deb.sh (TAG, TAG_COMMIT, KERNEL_GIT, SERIES, CPUS, MEM). One CPU is enough; nothing is built.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-${SPARKY_SCRATCH:?}/linux-stereo3d-config-proof}
[ $# -gt 0 ] && shift
FLAVOURS=${*:-base v3 rt}
TAG=${TAG:-v7.3-rc6}
TAG_COMMIT=${TAG_COMMIT:-a90ee4305c4a5df72c11b31dacfdc76e00fcf78a}
SERIES=${SERIES:-$HERE/series}
IMAGE=${IMAGE:-sparky-kernel-build:1}
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build --platform linux/amd64 -t "$IMAGE" "$HERE/docker"
mkdir -p "$OUT"
GITMOUNT=; [ -n "${KERNEL_GIT:-}" ] && GITMOUNT="-v $KERNEL_GIT:/kernel-git:ro"
# shellcheck disable=SC2086
docker run --rm --platform linux/amd64 --cpus "${CPUS:-2}" --memory "${MEM:-8g}" --user "$(id -u):$(id -g)" \
    -v "$OUT":/out -v "$HERE":/kernel:ro -v "$SERIES":/series:ro $GITMOUNT \
    -e TAG="$TAG" -e TAG_COMMIT="$TAG_COMMIT" -e FLAVOURS="$FLAVOURS" -e HAVE_KERNEL_GIT="${KERNEL_GIT:+1}" \
    "$IMAGE" sh -eu -c '
G=/kernel-git
if [ -z "${HAVE_KERNEL_GIT:-}" ]; then git clone --quiet --depth 1 --branch "$TAG" https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git /tmp/linux-git; G=/tmp/linux-git; fi
[ "$(git -C "$G" rev-parse "$TAG^{commit}")" = "$TAG_COMMIT" ] || { echo "tag $TAG is not $TAG_COMMIT"; exit 2; }
mkdir -p /tmp/src && git -C "$G" archive --format=tar "$TAG" | tar -x -C /tmp/src
cd /tmp/src
rc=0
for f in $FLAVOURS; do
    rm -rf /out/$f; mkdir -p /out/$f
    sh /series/apply-series.sh /tmp/src $( [ "$f" = base ] || echo "$f" ) >/out/$f/series.log
    case "$f" in rt) B=/kernel/config/debian-7.2.9-rt-amd64.config;; *) B=/kernel/config/debian-7.2.9-amd64.config;; esac
    mkdir -p /out/$f/deb-only && cp "$B" /out/$f/deb-only/.config && make -s O=/out/$f/deb-only olddefconfig
    sh /kernel/configure.sh "$f" /out/$f >/out/$f/configure.log 2>&1 || rc=1
    FR="/kernel/config/sparky-stereo.config"; [ -f /kernel/config/flavour-$f.config ] && FR="$FR /kernel/config/flavour-$f.config"
    python3 /kernel/tests/config-table.py "$f" /out/$f "$B" $FR > /out/$f/table.txt || rc=1
    tail -n 4 /out/$f/table.txt | head -n 1
    git -C /tmp/src status >/dev/null 2>&1 || true
    # the next flavour starts from a clean tree
    rm -rf /tmp/src && mkdir -p /tmp/src && git -C "$G" archive --format=tar "$TAG" | tar -x -C /tmp/src && cd /tmp/src
done
exit $rc'
