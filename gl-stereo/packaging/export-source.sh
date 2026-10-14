#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail
test -e /.dockerenv
test "$(id -u)" = 1000
repo=${GL_STEREO_SOURCE:-/K3D/temp/partners/gl-stereo/gl-stereo}
build=${GL_STEREO_BUILD:-/mnt/build/gl-stereo}
cd "$repo"
version=$(dpkg-parsechangelog -SVersion)
upstream=${version%-*}
# source-files is git ls-files -z, prepared after staging the source changes.
tar --exclude='debian' --exclude='debian/*' \
    --transform="s,^,gl-stereo-$upstream/," --mtime='2026-10-13 00:00:00Z' \
    --owner=0 --group=0 --numeric-owner -cf "$build/sources/gl-stereo_$upstream.orig.tar" --null -T "$build/source-files"
xz -f "$build/sources/gl-stereo_$upstream.orig.tar"
cd "$build/sources"
tar -xf gl-stereo_$upstream.orig.tar.xz
cp -a "$repo/debian" gl-stereo-$upstream/
