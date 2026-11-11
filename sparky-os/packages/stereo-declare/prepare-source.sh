#!/bin/bash
# Build the plain and LC source descriptors once, before either architecture.
# Usage (inside a prepared container): prepare-source.sh EMPTY_OUTPUT RELEASE_CLONE TOOLKIT
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export TMPDIR="${TMPDIR:?set a private assembly temporary directory}"
rev=675798f627e9010626acc9a32ed88d2f7e0349ba
version=1.10.0-1
prefix=stereo-declare-1.10.0
out=$(realpath -m "$1")
clone=$(realpath "$2")
toolkit=$(realpath "$3")
mkdir "$out"
mkdir "$out/plain" "$out/export" "$out/lc"
test "$(git -C "$clone" show "$rev":debian/changelog | head -1)" = "stereo-declare ($version) unstable; urgency=medium"
git -C "$clone" archive --format=tar --prefix="$prefix/" "$rev" | tar -x -C "$out/export"
cp -a "$out/export/$prefix/debian" "$out/debian-export"
rm -r "$out/export/$prefix/debian"
stamp=$(git -C "$clone" log -1 --format=%ct "$rev")
# The source is dated by its release commit, never by the clock (ORDER 421b); debian/ is normalized before each dpkg-source -b.
export SOURCE_DATE_EPOCH=$stamp
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$stamp" -C "$out/export" -cf - "$prefix" | xz -T4 -6 > "$out/plain/stereo-declare_1.10.0.orig.tar.xz"
cd "$out/plain"
tar -xf stereo-declare_1.10.0.orig.tar.xz
cp -a "$out/debian-export" "$prefix/debian"
python3 "$toolkit/repo/reproducible.py" normalize-tree "$stamp" "$prefix"
dpkg-source -b "$prefix"
cp ./*.tar.xz ./*.dsc "$out/lc/"
cd "$out/lc"
dpkg-source -x "stereo-declare_$version.dsc" source
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare "$out/lc/source" "$version+lc1" --toolkit "$toolkit" --build-dependency bubblewrap
# Retain this release's recorded LC changelog date before source assembly.
# The pipeline generates the entry; only its release timestamp is fixed here.
python3 - <<'DATE'
from pathlib import Path
p = Path('source/debian/changelog')
s = p.read_text()
head = s.split('\n\n', 1)[0]
assert head == 'stereo-declare (1.10.0-1+lc1) UNRELEASED; urgency=medium'
lines = s.splitlines(keepends=True)
index = next(i for i, line in enumerate(lines) if line.startswith(' -- '))
assert lines[index].startswith(' -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ')
lines[index] = lines[index].split('>  ', 1)[0] + '>  Tue, 10 Nov 2026 06:40:00 +0000\n'
p.write_text(''.join(lines))
DATE
# The sole LC descriptor is shared by both native architecture builds.
python3 "$toolkit/repo/reproducible.py" normalize-tree "$stamp" source
dpkg-source -b source
sha256sum ./*.dsc ./*.tar.xz > source-closure.sha256
