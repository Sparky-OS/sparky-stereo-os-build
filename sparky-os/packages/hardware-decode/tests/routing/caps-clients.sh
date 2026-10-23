#!/bin/sh
set -eu
unset __EGL_VENDOR_LIBRARY_FILENAMES MESA_LOADER_DRIVER_OVERRIDE DRI_PRIME
export WAYLAND_DISPLAY=order223-route LD_LIBRARY_PATH=/w/route-prefix/lib
exec > /w/logs/$SCENARIO-caps.log 2>&1
primary=vaapi
[ "$DISPLAY_GPU" = amd ] || primary=cuda
for name in h264-eyes8 h264-eyes10 hevc-eyes10 hevc-eyes12 h264-2d8 h264-right8 h264-cancel8 vp9-eyes8 vp9-eyes10; do
 expected=$primary
 case "$name" in h264-eyes10) expected=software;; hevc-eyes12) expected=cuda;; esac
 [ "${ONLY_AMD:-0}" != 1 ] || { [ "$name" != hevc-eyes12 ] || expected=software; }
 /w/decoder-choice /prev/fixtures/$name.mkv "$expected"
done
