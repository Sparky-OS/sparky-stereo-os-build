#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# ORDER 740: preserve published KPipeWire +8 and offer HEVC on every chosen link raster.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$here/../..")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
printf '%s  %s\n' cfbc9a3055dacb2130bb2eea27c1d9c2e436f7cdd85c1dddd342f7044214af21 "$input/kpipewire_6.7.4-1+stereo3d8.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 6.7.4-1+stereo3d9 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$here/overlay/debian" \
 --item 'Accept stereo packing for HEVC and size the software encoder from the packed raster, matching the existing per-eye filters (ORDER 740).' \
 --item 'Preserve the complete published +stereo3d8 source and package interfaces.' \
 "$input/kpipewire_6.7.4-1+stereo3d8.dsc" "$out"
