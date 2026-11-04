#!/bin/bash
# Restore the published source, append the reviewed patches, then prepare Lean Code.
# Usage: prepare-source.sh OUTPUT PUBLISHED_SOURCE_DIR TOOLKIT
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
input=$(realpath "$2")
toolkit=$(realpath "$3")
mkdir -p "$out"
mkdir "$out/plain" "$out/lc"
cd "$out/plain"
printf '%s  %s\n' 81c8091594a3b7e1a9d4ea44a7f4c56b508e0872d67f79e5ff8f2fa0d1de45f9 \
    "$input/kwin_6.7.4-2+stereo3d41+lc1.dsc" | sha256sum -c
cp "$input/kwin_6.7.4-2+stereo3d41+lc1.dsc" "$input/kwin_6.7.4-2+stereo3d41+lc1.debian.tar.xz" \
    "$input/kwin_6.7.4.orig.tar.xz" "$input/kwin_6.7.4.orig.tar.xz.asc" .
dpkg-source -x kwin_6.7.4-2+stereo3d41+lc1.dsc source
python3 "$toolkit/repo/plain-from-lc.py" source
cd source
grep -qx s41-0001-plugins-screenshot-Drop-X-KDE-DBUS-Restricted-Interf.patch debian/patches/series
for patch in "$HERE"/patches/s42-*.patch; do
    name=$(basename "$patch")
    ! grep -qx "$name" debian/patches/series
    cp "$patch" "debian/patches/$name"
    printf '%s\n' "$name" >> debian/patches/series
done
dpkg-source --before-build .
python3 - "$HERE/changelog-stereo3d42.txt" <<'CHANGELOG'
from pathlib import Path
import sys
p = Path('debian/changelog')
old = p.read_text()
assert old.startswith('kwin (4:6.7.4-2+stereo3d41) unstable;')
entry = Path(sys.argv[1]).read_text()
assert entry.startswith('kwin (4:6.7.4-2+stereo3d42) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n' + old)
assert 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d10~)' in Path('debian/control').read_text()
assert 'stereo_sequential_displayport' in Path('debian/rules').read_text()
# The published source already carries these binary fixtures and their listing.
for name in Path('debian/source/include-binaries').read_text().splitlines():
    assert Path(name).is_file(), name
CHANGELOG
cd ..
dpkg-source -b source
cp kwin_6.7.4-2+stereo3d42.dsc kwin_6.7.4-2+stereo3d42.debian.tar.xz \
    kwin_6.7.4.orig.tar.xz kwin_6.7.4.orig.tar.xz.asc "$out/lc/"
cd "$out/lc"
dpkg-source -x kwin_6.7.4-2+stereo3d42.dsc source
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare "$out/lc/source" \
    4:6.7.4-2+stereo3d42+lc1 --toolkit "$toolkit"
# Keep the accepted release's timestamp; the pipeline owns the entry and lc marker.
python3 - <<'DATE'
from pathlib import Path
p = Path('source/debian/changelog')
s = p.read_text()
assert s.startswith('kwin (4:6.7.4-2+stereo3d42+lc1) UNRELEASED;')
lines = s.splitlines(keepends=True)
index = next(i for i, line in enumerate(lines) if line.startswith(' -- '))
assert lines[index].startswith(' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ')
lines[index] = lines[index].split('>  ', 1)[0] + '>  Tue, 03 Nov 2026 23:40:25 +0000\n'
p.write_text(''.join(lines))
DATE
dpkg-source -b source
sha256sum ./*.dsc ./*.tar.xz ./*.asc > source-closure.sha256
