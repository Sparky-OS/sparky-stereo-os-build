#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
printf '%s  %s\n' 91006a03c42318f5c7c9d738cbdc13bc28a08a1db921e8f4edbe7c3775f8569b "$input/ums_15.9.0-1+stereo3d4+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 15.9.0-1+stereo3d5 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$here/overlay/debian" \
 --item 'Use KDE Connect pairing for Flat Headset movie control, GENA and media.' \
 --item 'Retain renderer-specific resources, panel sizing and full side-by-side frame packing.' \
 "$input/ums_15.9.0-1+stereo3d4+lc1.dsc" "$out"
