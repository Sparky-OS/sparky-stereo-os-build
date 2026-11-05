#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/05
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: ffmpeg-dmo 10:9.0.2-dmo1+stereo3d10(+lc1) from the published +stereo3d9+lc1 source (ORDER 410): patch 0052 replaced by
# the commit of pull request 25398, patch 0067 appended, changelog and Lean Code entries on top of the published history
# (repo/lc-successor.py --in-place --overlay; dch is not used).
#   next-source.sh PUBLISHED.dsc OUT          RED=1: the proof source +stereo3d10~red410 (the test, without the fix; never published)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
NEXT=10:9.0.2-dmo1+stereo3d10; [ "${RED:-}" = 1 ] && NEXT=10:9.0.2-dmo1+stereo3d10~red410
W=$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches"
cp "$HERE"/patches/*.patch "$W/overlay/patches/"
{ cat "$W/published/debian/patches/series"; [ "$(tail -c1 "$W/published/debian/patches/series" | xxd -p)" = 0a ] || echo; echo 0067-fate-test-hardware-state-cleanup-after-software-sele.patch; } > "$W/overlay/patches/series"
if [ "${RED:-}" = 1 ]; then
	sed -i '/^0052-/d' "$W/overlay/patches/series"; rm "$W/overlay/patches/0052-"*
fi
mapfile -t items < <(python3 - "$HERE/changelog.items" <<'PY'
import sys
for para in open(sys.argv[1], encoding='utf-8').read().strip().split('\n\n'):
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=(); for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next "$NEXT" "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
