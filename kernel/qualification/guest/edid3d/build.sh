#!/bin/bash
# build.sh HEADERS_DIR OUTDIR : builds edid3d.ko against the extracted headers package of a kernel (usr/src/linux-headers-REL), in the build image, as the invoking user.
# The EDID (edid.bin, edid_blob.h, expect.json) is made by make_edid.py. Nothing is installed.
set -eu
HDR=$(readlink -f "${1:?headers dir}"); OUT=$(mkdir -p "${2:?out dir}" && readlink -f "$2")
HERE=$(cd "$(dirname "$0")" && pwd)
python3 "$HERE/make_edid.py" "$OUT" >/dev/null
cp "$HERE/edid3d.c" "$HERE/Makefile" "$OUT/"
docker run --rm --platform linux/amd64 --cpus 2 --memory 4g --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$HDR":/hdr:ro -v "$OUT":/m kernel-soul-tools:1 sh -c 'make -C /hdr M=/m modules 2>&1 | tail -15'
ls -l "$OUT/edid3d.ko"
modinfo -F vermagic "$OUT/edid3d.ko" 2>/dev/null || true
