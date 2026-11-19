#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
printf '%s  %s\n' 71a475d1270e45379972f79f8977e81a3f1feb8e71493ebe9e33fdb9154d4741 "$input/krdp_6.7.4-1+stereo3d10.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 6.7.4-1+stereo3d11 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$here/overlay/debian" \
 --item 'Translate pairing refusal and revocation messages in all ten edition languages.' \
 --item 'Preserve the accepted HEVC paths and required systemd build dependency from ORDER 740.' \
 "$input/krdp_6.7.4-1+stereo3d10.dsc" "$out"
