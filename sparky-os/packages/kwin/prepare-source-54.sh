#!/bin/bash
# Restore the accepted +53 source, append the reviewed patches, then prepare Lean Code.
# Usage: prepare-source.sh OUTPUT PUBLISHED_SOURCE_DIR TOOLKIT
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
HERE=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
input=$(realpath "$2")
toolkit=$(realpath "$3")
# ORDER 421: the source's date is the recipe's, the date of its own changelog entry: no clock, zone, umask or checkout time
# reaches the bytes (SOURCE_DATE_EPOCH for dpkg-source's tar times, debian/ and its include-binaries normalized before each dpkg-source -b).
entry_date=$(sed -n 's/^ -- [^>]*>  //p' "$HERE/changelog-stereo3d54.txt" | head -1)
SOURCE_DATE_EPOCH=$(date -u -d "$entry_date" +%s)
export SOURCE_DATE_EPOCH
normalize() { python3 "$toolkit/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$1"; }
mkdir -p "$out"
mkdir "$out/plain" "$out/lc"
cd "$out/plain"
printf '%s  %s\n' da3d37ae11cf055851dd41ae24410257f3911c8e098df615ad08a715f4ee8828 \
    "$input/kwin_6.7.4-2+stereo3d53+lc1.dsc" | sha256sum -c
cp "$input/kwin_6.7.4-2+stereo3d53+lc1.dsc" "$input/kwin_6.7.4-2+stereo3d53+lc1.debian.tar.xz" \
    "$input/kwin_6.7.4.orig.tar.xz" "$input/kwin_6.7.4.orig.tar.xz.asc" .
dpkg-source -x kwin_6.7.4-2+stereo3d53+lc1.dsc source
python3 "$toolkit/repo/plain-from-lc.py" --save-plan "$out/published-preserve.json" source
cd source
# +53 carries every earlier patch, including ORDER 485's X11 limits.
grep -qx s53-0002-autotests-A-declared-X11-child-is-shown-only-where.patch debian/patches/series
for patch in "$HERE"/patches/s54-*.patch; do
    name=$(basename "$patch")
    ! grep -qx "$name" debian/patches/series
    cp "$patch" "debian/patches/$name"
    printf '%s\n' "$name" >> debian/patches/series
done
# Retain the previous notices and add Daniel's s54 patches to provenance.
python3 "$toolkit/repo/provenance-files.py" . 's??-????-*.patch'
dpkg-source --before-build .
python3 - "$HERE/changelog-stereo3d54.txt" <<'CHANGELOG'
from pathlib import Path
import sys
p = Path('debian/changelog')
old = p.read_text()
assert old.startswith('kwin (4:6.7.4-2+stereo3d53) unstable;')
entry = Path(sys.argv[1]).read_text()
assert entry.startswith('kwin (4:6.7.4-2+stereo3d54) unstable;')
p.write_text(entry.rstrip('\n') + '\n\n' + old)
assert 'plasma-wayland-protocols (>= 1.21.0-1+stereo3d10~)' in Path('debian/control').read_text()
assert 'libstereo-policy-dev (>= 1.15.0)' in Path('debian/control').read_text()
assert 'stereo_sequential_displayport' in Path('debian/rules').read_text()
# The published source already carries these binary fixtures and their listing.
for name in Path('debian/source/include-binaries').read_text().splitlines():
    assert Path(name).is_file(), name
CHANGELOG
cd ..
normalize source
dpkg-source -b source
cp kwin_6.7.4-2+stereo3d54.dsc kwin_6.7.4-2+stereo3d54.debian.tar.xz \
    kwin_6.7.4.orig.tar.xz kwin_6.7.4.orig.tar.xz.asc "$out/lc/"
cd "$out/lc"
dpkg-source -x kwin_6.7.4-2+stereo3d54.dsc source
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare "$out/lc/source" \
    4:6.7.4-2+stereo3d54+lc1 --toolkit "$toolkit" --preserve-plan "$out/published-preserve.json"
# The pipeline owns the entry and lc marker; its date is the recipe's (SOURCE_DATE_EPOCH, passed to dch by debian_prepare).
python3 - "$entry_date" <<'DATE'
import sys
from pathlib import Path
p = Path('source/debian/changelog')
s = p.read_text()
assert s.startswith('kwin (4:6.7.4-2+stereo3d54+lc1) UNRELEASED;')
lines = s.splitlines(keepends=True)
index = next(i for i, line in enumerate(lines) if line.startswith(' -- '))
assert lines[index].startswith(' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ')
assert lines[index].split('>  ', 1)[1].strip() == sys.argv[1], (lines[index], sys.argv[1])
DATE
normalize source
dpkg-source -b source
sha256sum ./*.dsc ./*.tar.xz ./*.asc > source-closure.sha256
