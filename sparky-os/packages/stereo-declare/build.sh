#!/bin/bash
# Prepare source once, then build both native architectures from that descriptor.
# Usage: build.sh source WORK CLONE IMAGE
#        build.sh binary WORK SOURCE_DIR PREVIOUS_DIR IMAGE amd64|i386
# IMAGE is an existing prepared SDK. Archive configuration/keyring paths must be
# container paths beneath /archive. The coordinator supplies its resource guard.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
mode=$1
WORK=$(realpath -m "$2")
[ ! -e "$WORK" ] || { echo "$WORK already exists" >&2; exit 1; }
mkdir -p "$WORK"
if [ "$mode" = source ]; then
    CLONE=$(realpath "$3")
    : "${SPARKY_LC_TOOLKIT:?the reviewed current toolkit directory}"
    docker run --rm --cpus 4 --platform linux/amd64 --user "$(id -u):$(id -g)" \
        -v "$WORK":/work -v "$CLONE":/fork:ro -v "$SPARKY_LC_TOOLKIT":/toolkit:ro -v "$HERE":/tools:ro \
        "$4" bash -c 'mkdir /work/tmp; TMPDIR=/work/tmp bash /tools/prepare-source.sh /work/source /fork /toolkit'
elif [ "$mode" = binary ]; then
    SRC=$(realpath "$3")
    PREV=$(realpath "$4")
    case "$6" in amd64) platform=linux/amd64 ;; i386) platform=linux/386 ;; *) exit 1 ;; esac
    : "${SPARKY_LC_ARCHIVE_DIR:?public sources.json and public keyrings}"
    docker run --rm --cpus 4 --platform "$platform" --user "$(id -u):$(id -g)" \
        --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
        -v "$WORK":/work -v "$SRC":/src:ro -v "$PREV":/prev:ro -v "$HERE":/tools:ro \
        -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro "$5" \
        bash /tools/build-in-container.sh /work/build /src/stereo-declare_1.8.0-1+lc1.dsc /prev /archive/sources.json
else
    echo 'Expected source or binary' >&2
    exit 1
fi
