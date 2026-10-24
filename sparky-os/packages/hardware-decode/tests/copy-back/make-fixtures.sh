#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# Recorded H.264 High films for the copy-back matrix, 1920x1080 at 24 fps:
# 2D; side by side left first with the display size of the frame (read as
# full views, sbsl) and with the pair's full width as display size, sample
# aspect ratio 2:1 as in the A10's Life of Pi 3D (read as half views, sbs2l);
# and top and bottom left first. Each is declared by Matroska StereoMode
# (RFC 9559 5.1.4.1.28.3: 1 side by side left eye first, 3 top and bottom
# left eye first). The two views differ in hue, so a swapped or merged view
# shows in a capture.
# Usage: make-fixtures.sh OUTDIR
set -euo pipefail
out=$1
mkdir -p "$out"
x264=(-c:v libx264 -preset medium -profile:v high -pix_fmt yuv420p -g 24 -bf 2 -t 6)
ffmpeg -v error -y -f lavfi -i testsrc2=s=1920x1080:r=24 "${x264[@]}" "$out/2d.mkv"
ffmpeg -v error -y -filter_complex \
    'testsrc2=s=960x1080:r=24[a];testsrc2=s=960x1080:r=24,hue=h=180[b];[a][b]hstack' \
    "${x264[@]}" -metadata:s:v:0 stereo_mode=left_right "$out/sbs.mkv"
ffmpeg -v error -y -filter_complex \
    'testsrc2=s=960x1080:r=24[a];testsrc2=s=960x1080:r=24,hue=h=180[b];[a][b]hstack,setsar=2' \
    "${x264[@]}" -metadata:s:v:0 stereo_mode=left_right "$out/sbs2.mkv"
ffmpeg -v error -y -filter_complex \
    'testsrc2=s=1920x540:r=24[a];testsrc2=s=1920x540:r=24,hue=h=180[b];[a][b]vstack' \
    "${x264[@]}" -metadata:s:v:0 stereo_mode=top_bottom "$out/tb.mkv"
(cd "$out" && sha256sum 2d.mkv sbs.mkv sbs2.mkv tb.mkv > fixtures.sha256)
