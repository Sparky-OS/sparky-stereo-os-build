#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/09, last update 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: the next +lc1 source of mesa, +stereo3d22 (ORDER 561): the +stereo3d21+lc1 source unpacked, patch 0038
# appended to its series, the glx-pair-copied test added to debian/tests, the two problems' messages (lang/) as debian/lang,
# debian/control, control.in and rules changed for sparky-stereo-problems (debian-changes.py: build dependency, dependency
# and journal catalogs on amd64, the meson option on every architecture), a postrm that ends the package's problems, and the
# changelog entry of the plain version then the Lean Code entry on top of the published history (repo/lc-successor.py
# --in-place --overlay), so the old changelog stays a byte identical suffix. prepare-source.sh stays the +stereo3d19 recipe
# (it starts from the +stereo3d17 source).
#   next-source.sh PUBLISHED.dsc OUT
#   PUBLISHED.dsc: the +stereo3d21+lc1 source (its orig tarball beside it)
#   OUT: receives the new .dsc, Debian tarball, both changelogs and the successor report
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../repo" && pwd)
DSC=$(readlink -f "$1") OUT=$2
SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(python3 "$REPO/reproducible.py" epoch "$HERE")}
export SOURCE_DATE_EPOCH
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
[ "$(sed -n 's/^Version: //p' "$DSC")" = '26.1.6-1+stereo3d21+lc1' ] || { echo "the source must be 26.1.6-1+stereo3d21+lc1" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/mesa-source-XXXXXX")
trap 'rm -rf "$W"' EXIT
dpkg-source --skip-patches -x "$DSC" "$W/published" >/dev/null
mkdir -p "$W/overlay/patches" "$W/overlay/tests" "$W/overlay/lang"
cp "$W/published/debian/patches/series" "$W/overlay/patches/series"
[ -z "$(tail -c1 "$W/overlay/patches/series")" ] || echo >> "$W/overlay/patches/series"
for p in 0038-glx-a-stereo-window-whose-pair-the-x-server-copies-is-shown-flat-and-told.patch; do
	grep -qxF "$p" "$W/published/debian/patches/series" && { echo "the source already has $p" >&2; exit 2; }
	cp "$HERE/patches/$p" "$W/overlay/patches/"
	echo "$p" >> "$W/overlay/patches/series"
done
cp "$HERE/tests/glx-covered.c" "$HERE/glx-pair-copied" "$W/overlay/tests/"
cat "$W/published/debian/tests/control" - > "$W/overlay/tests/control" <<'CTL'

Tests: glx-pair-copied
Depends: build-essential, libgl1-mesa-dev, libx11-dev, libglx-mesa0, libgl1-mesa-dri, xvfb
Restrictions: skippable
CTL
# the messages of the two problems GLX keeps, in the ten languages; debian/rules makes journal catalogs of them
for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
	cp "$HERE/lang/$l" "$W/overlay/lang/$l"
done
cat > "$W/overlay/libglx-mesa0.postrm" <<'POSTRM'
#!/bin/sh
# postrm script
set -e
# the problems this package kept go with it (the engine may be gone already: Debian Policy 6.5)
if { [ "$1" = remove ] || [ "$1" = purge ]; } && command -v sparky-stereo-problems >/dev/null 2>&1; then
	sparky-stereo-problems clear --all libglx-mesa0 ||
		echo "libglx-mesa0: its kept problems could not be ended (sparky-stereo-problems clear --all libglx-mesa0)" >&2
fi

#DEBHELPER#

exit 0
POSTRM
python3 "$HERE/debian-changes.py" "$W/published/debian" "$W/overlay"
mapfile -t items < <(python3 - "$HERE/changelog-stereo3d22.txt" <<'PY'
import sys
import re
text = open(sys.argv[1], encoding='utf-8').read().split('\n\n', 1)[1]
for para in re.split(r'(?m)^  \* ', text.strip('\n'))[1:]:
    print(' '.join(l.strip() for l in para.splitlines()))
PY
)
args=()
for i in "${items[@]}"; do args+=(--item "$i"); done
python3 "$REPO/lc-successor.py" --in-place --next 26.1.6-1+stereo3d22 "${args[@]}" --overlay "$W/overlay" --work "$W" "$DSC" "$OUT"
