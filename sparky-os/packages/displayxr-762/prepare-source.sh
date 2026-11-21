#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
packaging=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
commit=9d8e034e03050f2e0eba0214d33263185c44f129
[ "$(git -C "$packaging" rev-parse HEAD)" = "$commit" ] || { echo 'Unexpected packaging commit' >&2; exit 1; }
overlay=$(mktemp -d "${SD762_SCRATCH:?}/runtime-overlay.XXXXXX")
trap 'rm -r -- "$overlay"' EXIT
git -C "$packaging" archive "$commit" debian/patches/series debian/patches/0021-declared-pair-screen-segmentation.patch | tar -x -C "$overlay"
printf '%s  %s\n' 90ef70dcef626180e1222704d48b1d75232f7f5e1d20c97691e7d09edc551ec5 "$input/displayxr-runtime_2.66.3-1+stereo3d9+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 2.66.3-1+stereo3d10 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$overlay/debian" \
 --item 'Keep declared full side-by-side pairs intact for Stereo KWin instead of applying physical-screen segmentation.' \
 "$input/displayxr-runtime_2.66.3-1+stereo3d9+lc1.dsc" "$out"
