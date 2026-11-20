#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
printf '%s  %s\n' 34ee34753042f6687a05e9d63e2e036e206b13c64295db32b27aaf254daf32a7 "$input/krdp_6.7.4-1+stereo3d11.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 6.7.4-1+stereo3d12 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$here/overlay/debian" \
 --item 'Carry the accepted RDP sensor channel and bind it to approved paired panel leases.' \
 --item 'Deliver bounded orientation to the local OpenXR source and report unavailable runtimes explicitly.' \
 "$input/krdp_6.7.4-1+stereo3d11.dsc" "$out"
