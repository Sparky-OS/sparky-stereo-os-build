#!/bin/bash
# Build the plain and LC source descriptors once, before either architecture.
# Usage (inside a prepared container): prepare-source.sh EMPTY_OUTPUT RELEASE_CLONE TOOLKIT
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export TMPDIR="${TMPDIR:?set a private assembly temporary directory}"
rev=09f74f8bb2f880b1fbafc7b8d1fa8b763873286c
version=1.8.0-1
prefix=stereo-declare-1.8.0
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
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@$stamp" -C "$out/export" -cf - "$prefix" | xz -T4 -6 > "$out/plain/stereo-declare_1.8.0.orig.tar.xz"
cd "$out/plain"
tar -xf stereo-declare_1.8.0.orig.tar.xz
cp -a "$out/debian-export" "$prefix/debian"
dpkg-source -b "$prefix"
cp ./*.tar.xz ./*.dsc "$out/lc/"
cd "$out/lc"
dpkg-source -x "stereo-declare_$version.dsc" source
PYTHONPATH="$toolkit" python3 -m lean.debian_prepare "$out/lc/source" "$version+lc1" --toolkit "$toolkit" --build-dependency bubblewrap
# The sole LC descriptor is shared by both native architecture builds.
dpkg-source -b source
sha256sum ./*.dsc ./*.tar.xz > source-closure.sha256
