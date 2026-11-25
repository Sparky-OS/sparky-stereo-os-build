#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# The video wallpaper and lock screen plugin org.kde.video, by Jeromy Streets: his Plasma 6 port as merged in
# Sparky-OS/org.kde.video (branch stereo3d, pull request 26), packaged unchanged (queue row 96). This script makes the
# unpacked source and its orig tarball from a clone of that repository, and refuses any other commit or tree: the commit,
# its tree and the SHA-256 of `git archive` are pinned below. No patch of ours is applied; debian/ is the recipe's.
# Usage: make-source.sh CLONE WORK    (makes WORK/SOURCE and WORK/NAME_UPSTREAM.orig.tar.xz for release/build-dh-lean.sh)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CLONE=${1:?a clone of https://github.com/Sparky-OS/org.kde.video} WORK=${2:?work folder}
COMMIT=15035dc949a0105b4d70a4abf14c19af564154a5
TREE=404959316433f6b3d7985e19f00a6e062f1cc46d
ARCHIVE_SHA256=3ce5fa9213577d7680692c1f6bf0d418b1a9bcdb589737b1e0179434ee263b52
NAME=qml-module-org-kde-video-wallpaper UPSTREAM=2.0.0~git20261029.15035dc9
[ "$(git -C "$CLONE" rev-parse "$COMMIT^{commit}")" = "$COMMIT" ] || { echo "the clone does not hold commit $COMMIT" >&2; exit 1; }
[ "$(git -C "$CLONE" rev-parse "$COMMIT^{tree}")" = "$TREE" ] || { echo "commit $COMMIT does not have tree $TREE" >&2; exit 1; }
mkdir -p "$WORK"
tar=$(mktemp "$WORK/.archive.XXXXXX"); trap 'rm -f "$tar"' EXIT
git -C "$CLONE" archive --format=tar --prefix="$NAME-$UPSTREAM/" "$COMMIT" > "$tar"
# the pin is on the archive without a prefix change: the same bytes on any machine with the same git archive format
[ "$(git -C "$CLONE" archive --format=tar --prefix=org.kde.video-15035dc9/ "$COMMIT" | sha256sum | cut -d' ' -f1)" = "$ARCHIVE_SHA256" ] \
    || { echo "git archive of $COMMIT is not the pinned one ($ARCHIVE_SHA256)" >&2; exit 1; }
xz -T1 -6 -c "$tar" > "$WORK/${NAME}_$UPSTREAM.orig.tar.xz"
rm -rf "$WORK/source"; mkdir "$WORK/source"
tar -xf "$tar" -C "$WORK/source" --strip-components=1
cp -r "$HERE/debian" "$WORK/source/debian"
echo "$WORK/source and $WORK/${NAME}_$UPSTREAM.orig.tar.xz"
