#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
packaging=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
commit=1d092ef950bb650ba06baf35e0c0461b2594d3be
[ "$(git -C "$packaging" rev-parse HEAD)" = "$commit" ] || { echo 'Unexpected packaging commit' >&2; exit 1; }
overlay=$(mktemp -d "${SD762_SCRATCH:?}/runtime-overlay.XXXXXX")
trap 'rm -rf "$overlay"' EXIT
git -C "$packaging" archive "$commit" debian/patches/series debian/patches/0012-paired-phone-orientation-and-accepted-input.patch debian/patches/0013-attach-stress-reader-before-writer.patch | tar -x -C "$overlay"
printf '%s  %s\n' 6202ccda33f09ec609ee6c336063c359afa0c754de0be118957a5f7a962b90f8 "$input/displayxr-runtime_2.66.3-1+stereo3d3+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 2.66.3-1+stereo3d4 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$overlay/debian" \
 --item 'Carry the accepted numeric stereo layout, depth and gamepad work with the paired RDP orientation source.' \
 --item 'Preserve full-SBS-only output, declaration failure reporting and per-eye display zones.' \
 --item 'Attach the stress reader on the empty page before starting the writer; keep its assertions and the product reader unchanged.' \
 "$input/displayxr-runtime_2.66.3-1+stereo3d3+lc1.dsc" "$out"
