#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
printf '%s  %s\n' cb615b0271b0900f485dfa79ddf05d39d7b0fd28e904512fb340108c373d4ed5 "$input/krdp_6.7.4-1+stereo3d9.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 6.7.4-1+stereo3d10 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$here/overlay/debian" \
 --item 'Require current KDE Connect mutual certificate trust for headset control over SSDP and USB networking; revoke pending and live display leases on unpairing.' \
 --item 'Preserve the accepted HEVC paths and required systemd build dependency from ORDER 740.' \
 "$input/krdp_6.7.4-1+stereo3d9.dsc" "$out"
