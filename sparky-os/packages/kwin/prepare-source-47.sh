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
# ORDER 421: the source's date is the recipe's, the date of its own changelog entry: no clock, zone, umask or checkout time
# reaches the bytes (SOURCE_DATE_EPOCH for dpkg-source's tar times, debian/ and its include-binaries normalized before each dpkg-source -b).
entry_date=$(sed -n 's/^ -- [^>]*>  //p' "$HERE/changelog-stereo3d47.txt" | head -1)
SOURCE_DATE_EPOCH=$(date -u -d "$entry_date" +%s)
export SOURCE_DATE_EPOCH
normalize() { python3 "$toolkit/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" "$1"; }
mkdir -p "$out"
mkdir "$out/plain" "$out/lc"
cd "$out/plain"
printf '%s  %s\n' a4244ddef20f7b1428381d02c09899a810d29476e1d4079f7ccc57b1c42a9fdd \
    "$input/kwin_6.7.4-2+stereo3d43+lc1.dsc" | sha256sum -c
cp "$input/kwin_6.7.4-2+stereo3d43+lc1.dsc" "$input/kwin_6.7.4-2+stereo3d43+lc1.debian.tar.xz" \
    "$input/kwin_6.7.4.orig.tar.xz" "$input/kwin_6.7.4.orig.tar.xz.asc" .
dpkg-source -x kwin_6.7.4-2+stereo3d43+lc1.dsc source
python3 "$toolkit/repo/plain-from-lc.py" --save-plan "$out/published-preserve.json" source
cd source
grep -qx s43-0002-autotests-The-depth-limits-follow-the-output.patch debian/patches/series
for patch in "$HERE"/patches/s44-*.patch "$HERE"/patches/s45-*.patch "$HERE"/patches/s46-*.patch "$HERE"/patches/s47-*.patch; do
    name=$(basename "$patch")
    ! grep -qx "$name" debian/patches/series
    cp "$patch" "debian/patches/$name"
    printf '%s\n' "$name" >> debian/patches/series
done
# Names only in the headers of the commits carried from upstream: the invent commit URL in Origin: carries the full record, and
# no third-party address is kept in our files. s47-0001..0003 are written so; the published s41-0001 is rewritten here.
sed -i -E '1,40{/^(From|Author|Co-authored-by): /s/ *<[^>]*>//}' debian/patches/s41-0001-*.patch
# ORDER 451: the patches of ours, for the copyright file (provenance.sh): read from each patch's header, a carried upstream
# commit (s41-0001, s47-0001..0003) stays its author's
python3 "$toolkit/repo/provenance-files.py" . 's??-????-*.patch'
dpkg-source --before-build .
python3 - "$HERE/changelog-stereo3d44.txt" "$HERE/changelog-stereo3d45.txt" "$HERE/changelog-stereo3d46.txt" "$HERE/changelog-stereo3d47.txt" <<'CHANGELOG'
from pathlib import Path
import sys
p = Path('debian/changelog')
old = p.read_text()
assert old.startswith('kwin (4:6.7.4-2+stereo3d43) unstable;')
# +stereo3d44 (ORDER 418), +stereo3d45 (ORDER 424) and +stereo3d46 (ORDER 442) were never published on their own: this source carries their entries and patches, then +stereo3d47
entry44 = Path(sys.argv[1]).read_text()
entry45 = Path(sys.argv[2]).read_text()
entry46 = Path(sys.argv[3]).read_text()
entry47 = Path(sys.argv[4]).read_text()
assert entry44.startswith('kwin (4:6.7.4-2+stereo3d44) unstable;')
assert entry45.startswith('kwin (4:6.7.4-2+stereo3d45) unstable;')
assert entry46.startswith('kwin (4:6.7.4-2+stereo3d46) unstable;')
assert entry47.startswith('kwin (4:6.7.4-2+stereo3d47) unstable;')
p.write_text(entry47.rstrip('\n') + '\n\n' + entry46.rstrip('\n') + '\n\n' + entry45.rstrip('\n') + '\n\n' + entry44.rstrip('\n') + '\n\n' + old)
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
cp kwin_6.7.4-2+stereo3d47.dsc kwin_6.7.4-2+stereo3d47.debian.tar.xz \
    kwin_6.7.4.orig.tar.xz kwin_6.7.4.orig.tar.xz.asc "$out/lc/"
cd "$out/lc"
dpkg-source -x kwin_6.7.4-2+stereo3d47.dsc source
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare "$out/lc/source" \
    4:6.7.4-2+stereo3d47+lc1 --toolkit "$toolkit" --preserve-plan "$out/published-preserve.json"
# The pipeline owns the entry and lc marker; its date is the recipe's (SOURCE_DATE_EPOCH, passed to dch by debian_prepare).
python3 - "$entry_date" <<'DATE'
import sys
from pathlib import Path
p = Path('source/debian/changelog')
s = p.read_text()
assert s.startswith('kwin (4:6.7.4-2+stereo3d47+lc1) UNRELEASED;')
lines = s.splitlines(keepends=True)
index = next(i for i, line in enumerate(lines) if line.startswith(' -- '))
assert lines[index].startswith(' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ')
assert lines[index].split('>  ', 1)[1].strip() == sys.argv[1], (lines[index], sys.argv[1])
DATE
normalize source
dpkg-source -b source
sha256sum ./*.dsc ./*.tar.xz ./*.asc > source-closure.sha256
