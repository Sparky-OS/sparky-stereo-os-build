#!/bin/bash
# Build one native architecture from the shared stereo-declare 1.8 descriptor.
# Usage: build-in-container.sh EMPTY_OUTPUT DSC PREVIOUS_DIR ARCHIVE_CONFIG
# The caller supplies a prepared native SDK and a namespace-capable runner.
set -euo pipefail
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS LD_LIBRARY_PATH LD_PRELOAD
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export DEB_BUILD_OPTIONS=parallel=4 PYTHONDONTWRITEBYTECODE=1
out=$(realpath -m "$1")
dsc=$(realpath "$2")
export SPARKY_LC_PREVIOUS_DIR=$(realpath "$3")
export SPARKY_LC_ARCHIVE_CONFIG=$(realpath "$4")
eval "$(dpkg-architecture -s)"
case "$DEB_HOST_ARCH:$DEB_HOST_ARCH_BITS" in
    amd64:64) kind=-b ;;
    i386:32) kind=-B ;;
    *) echo 'This recipe qualifies native amd64 and i386 only' >&2; exit 1 ;;
esac
mkdir "$out"
mkdir "$out/tmp"
export TMPDIR="$out/tmp" SPARKY_LC_SCRATCH="$out/link-scratch"
cd "$out"
dpkg-source -x "$dsc" source
cd source
test "$(dpkg-parsechangelog -S Version)" = 1.8.0-1+lc1
# dpkg derives SOURCE_DATE_EPOCH from this one descriptor's changelog.
dpkg-buildpackage -us -uc "$kind" -j4
PYTHONPATH="$PWD/debian/sparky-lean-toolkit" python3 -m lean.release check-debs "$out"/*.deb
