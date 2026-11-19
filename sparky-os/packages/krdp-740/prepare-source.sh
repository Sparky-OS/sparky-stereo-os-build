#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
# ORDER 740: preserve published KRdp +8 and offer HEVC on every chosen link raster.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
toolkit=$(realpath "$here/../..")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
printf '%s  %s\n' 157b533e4372eb351baa2fcdd752d4f28f5d92a1ef59ae6dba43fdc689fcc3b5 "$input/krdp_6.7.4-1+stereo3d8.dsc" | sha256sum -c
python3 "$toolkit/repo/lc-successor.py" --in-place --next 6.7.4-1+stereo3d9 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$here/overlay/debian" \
 --item 'Offer the authenticated HEVC channel on every headset link format, using the same encoded raster, packing and refresh as H.264. Keep every route and H.264 as the default (ORDER 740).' \
 --item 'Preserve the complete published +stereo3d8 source and package interfaces.' \
 --item 'Declare systemd development and test-session D-Bus dependencies; retain the settings module service controls and journal support.' \
 "$input/krdp_6.7.4-1+stereo3d8.dsc" "$out"
