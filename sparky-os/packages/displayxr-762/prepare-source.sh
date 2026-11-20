#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
packaging=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
commit=dd40735d8f4aa28f20da3feb0c887e3c704388fb
[ "$(git -C "$packaging" rev-parse HEAD)" = "$commit" ] || { echo 'Unexpected packaging commit' >&2; exit 1; }
overlay=$(mktemp -d "${SD762_SCRATCH:?}/runtime-overlay.XXXXXX")
trap 'rm -rf "$overlay"' EXIT
git -C "$packaging" archive "$commit" debian/patches/series debian/patches/0014-paired-origin-change-events.patch | tar -x -C "$overlay"
printf '%s  %s\n' 2fa6f88aa562430bcbdcab09230b17b2510f5bafc11a48fc62a399e9b51b3058 "$input/displayxr-runtime_2.66.3-1+stereo3d4+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 2.66.3-1+stereo3d5 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$overlay/debian" \
 --item 'Notify reference-space changes at mapped capture time and keep pre-change queries in the previous origin.' \
 --item 'Treat a new paired source as a new reference even when its origin serial repeats; retain every existing suite test.' \
 "$input/displayxr-runtime_2.66.3-1+stereo3d4+lc1.dsc" "$out"
