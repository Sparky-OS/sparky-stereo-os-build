#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
# rerun-m2.sh BASE_IMAGE PUBLISHED_APT_REPO STAGE_M1 STAGE_M2 RESULTS
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
base=$1 repo=$(realpath "$2") m1=$(realpath "$3") m2=$(realpath "$4")
out=$(mkdir -p "$5" && cd "$5" && pwd -P)
prefix=${PREFIX:?use the lane prefix}
red_image=$prefix:paper-depth-red
green_image=$prefix:paper-depth-green
[ -z "$(ls -A "$out")" ] || { echo "$out is not empty" >&2; exit 2; }

df -B1 --output=avail / /mnt/build /K3D | tee "$out/disk-before-red-image.txt"
WITH_WORDS=1 PREFIX=$prefix-red "$here/rig-image.sh" "$base" "$red_image" "$repo" \
    "$m1/kwin" "$m1/qt6-base" "$m1/plasma-wayland-protocols" "$m1/okular" | tee "$out/red-image.log"
df -B1 --output=avail / /mnt/build /K3D | tee "$out/disk-before-green-image.txt"
WITH_WORDS=1 PREFIX=$prefix-green "$here/rig-image.sh" "$base" "$green_image" "$repo" \
    "$m2/kwin" "$m2/qt6-base" "$m2/plasma-wayland-protocols" "$m2/calligra" "$m1/okular" | tee "$out/green-image.log"

expanded='okular-display preview-display probe-override words-3d words-scrolled words-background words-2d'
reference='okular-3d okular-scale12 okular-limit0 okular-scrolled okular-presentation okular-background okular-2d
preview-3d preview-scale12 preview-limit0 preview-scrolled preview-background preview-2d'
M2=1 CASES="$expanded okular-2d preview-2d" PREFIX=$prefix-red "$here/run.sh" "$red_image" "$out/red" capture
M2=1 CASES="$reference $expanded okular-kcm" PREFIX=$prefix-green BASELINE="$out/red" \
    "$here/run.sh" "$green_image" "$out/green" staged
python3 -I "$here/verdicts-m2.py" "$out/red" "$out/green" | tee "$out/m2-verdicts.txt"

df -B1 --output=avail / /mnt/build /K3D | tee "$out/disk-before-apt.txt"
PREFIX=$prefix "$here/apt-m2.sh" "$base" "$repo" "$m1" "$m2" "$out/apt"
docker rmi "$green_image" "$red_image"
