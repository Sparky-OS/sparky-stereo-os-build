#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
packaging=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
commit=da1f2fa3296fb1e6f187de3813cfb4373caaca6a
[ "$(git -C "$packaging" rev-parse HEAD)" = "$commit" ] || { echo 'Unexpected packaging commit' >&2; exit 1; }
overlay=$(mktemp -d "${SD762_SCRATCH:?}/runtime-overlay.XXXXXX")
trap 'rm -rf "$overlay"' EXIT
git -C "$packaging" archive "$commit" debian/patches/series debian/patches/0017-paired-headset-problem.patch debian/control debian/rules debian/lang | tar -x -C "$overlay"
printf '%s  %s\n' c15ce7983ba654caeefa7fbfc9c8f59cebdda013845d00d942e362a615d84261 "$input/displayxr-runtime_2.66.3-1+stereo3d6+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 2.66.3-1+stereo3d7 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$overlay/debian" \
 --item 'Tell the person which process owns the paired headset through the failure engine, and clear the problem on successful acquisition; retain the OpenXR result.' \
 "$input/displayxr-runtime_2.66.3-1+stereo3d6+lc1.dsc" "$out"
