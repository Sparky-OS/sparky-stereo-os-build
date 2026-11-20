#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
input=$(realpath "$1")
out=$(realpath -m "$2")
packaging=$(realpath "$3")
: "${SOURCE_DATE_EPOCH:?set to the committed recipe date}"
commit=cecb2928c418b515fc5765d23002e92e97d273c5
[ "$(git -C "$packaging" rev-parse HEAD)" = "$commit" ] || { echo 'Unexpected packaging commit' >&2; exit 1; }
overlay=$(mktemp -d "${SD762_SCRATCH:?}/runtime-overlay.XXXXXX")
trap 'rm -rf "$overlay"' EXIT
git -C "$packaging" archive "$commit" debian/patches/series debian/patches/0016-paired-socket-ownership.patch | tar -x -C "$overlay"
printf '%s  %s\n' 9ab9885d59412b7d1defdb3def1b789cd1926a8752e642dc4fe15e9b9cd2504f "$input/displayxr-runtime_2.66.3-1+stereo3d5+lc1.dsc" | sha256sum -c
python3 "$here/../../repo/lc-successor.py" --in-place --next 2.66.3-1+stereo3d6 \
 --source-date-epoch "$SOURCE_DATE_EPOCH" --overlay "$overlay/debian" \
 --item 'Recover refused same-user paired headset sockets, refuse live or foreign owners explicitly, and remove only the owned socket at shutdown.' \
 "$input/displayxr-runtime_2.66.3-1+stereo3d5+lc1.dsc" "$out"
