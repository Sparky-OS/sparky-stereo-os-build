#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# build-igt-root.sh SRC_DIR OUT_DIR
#   Builds IGT GPU Tools at the commit the patches of ../igt were written on, with them applied, in the image
#   that will be the guest's root (as the invoking user, 4 CPUs), then exports that image into OUT_DIR with
#   kms_frame_sequential, libigt and the stereo pictures igt_create_stereo_fb() paints in /usr/local.
#   SRC_DIR receives the IGT clone and the build.
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
IGT_COMMIT=aa47394363f196686c3a9d54691f7291dacb0592
IMAGE=${IMAGE:-dp-stereo-257-m3-bench:1}
SRC=$(mkdir -p "$1" && readlink -f "$1"); OUT=$(mkdir -p "$2" && readlink -f "$2")
[ -d "$SRC/igt/.git" ] || git clone -q https://gitlab.freedesktop.org/drm/igt-gpu-tools.git "$SRC/igt"
git -C "$SRC/igt" checkout -q --detach "$IGT_COMMIT"
git -C "$SRC/igt" -c user.name=bench -c user.email=bench@localhost am -q "$HERE"/../igt/*.patch
docker run --rm --platform linux/amd64 --cpus 4 --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$SRC:$SRC" "$IMAGE" sh -c "
	meson setup --wipe '$SRC/build' '$SRC/igt' -Dprefix=/usr/local -Dtests=enabled -Drunner=disabled \
		-Dchamelium=disabled -Dvalgrind=disabled -Dman=disabled -Ddocs=disabled -Doverlay=disabled \
		-Dtestplan=disabled -Dsphinx=disabled -Dlibdrm_drivers= -Dvmtb=disabled -Doping=disabled \
		-Dlibunwind=enabled -Dxe_driver=disabled >/dev/null &&
	ninja -C '$SRC/build' -j4 tests/kms_frame_sequential"
cid=$(docker create --platform linux/amd64 "$IMAGE")
docker export "$cid" | tar -x -C "$OUT" 2>/dev/null || true
docker rm "$cid" >/dev/null
mkdir -p "$OUT/usr/local/bin" "$OUT/usr/local/lib" "$OUT/usr/local/share/igt-gpu-tools"
cp "$SRC/build/tests/kms_frame_sequential" "$OUT/usr/local/bin/"
cp -L "$SRC/build/lib/libigt.so.0" "$OUT/usr/local/lib/"
cp "$SRC/igt/data/1080p-left.png" "$SRC/igt/data/1080p-right.png" "$OUT/usr/local/share/igt-gpu-tools/"
echo "IGT root: $OUT (IGT $(git -C "$SRC/igt" log -1 --format=%h), $(git -C "$SRC/igt" log -1 --format=%s))"
