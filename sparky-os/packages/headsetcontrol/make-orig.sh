#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Makes the upstream archive of headsetcontrol 4.3.0, byte for byte the same each time:
#   headsetcontrol_4.3.0.orig.tar.xz   the release tag's tree, pinned by its commit and by its git tree id
# Usage: make-orig.sh OUTDIR   (needs curl, git, xz, python3 and the network; the package build itself reads none)
set -euo pipefail
umask 022
OUT=${1:?output folder}
VERSION=4.3.0
TAG_SHA256=d05f9e18e8d2783109c54efe4e77ad1765b008f2ee13a028521ad37fe3e2a2b9   # codeload tar.gz of refs/tags/4.3.0
COMMIT=62e361b085d7716805a3bf524bc9cca3761e0e15                                  # the tag is annotated: its tarball names this commit
TREE=29d2e85f7f3c2932fd11540e05079267025c7a51                                    # that commit's git tree
MTIME=2026-11-13T15:59:22Z                                                       # that commit's committer date
W=$(mktemp -d "${TMPDIR:-/tmp}/headsetcontrol-orig.XXXXXX")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$OUT"
curl -fsSL "https://codeload.github.com/Sapd/HeadsetControl/tar.gz/refs/tags/$VERSION" -o "$W/tag.tar.gz"
echo "$TAG_SHA256  $W/tag.tar.gz" | sha256sum -c -
python3 - "$W/tag.tar.gz" "$COMMIT" <<'PY'
import sys, tarfile
comment = tarfile.open(sys.argv[1]).pax_headers.get('comment')
if comment != sys.argv[2]:
	sys.exit(f'the archive names commit {comment}, the recipe pins {sys.argv[2]}')
PY
mkdir "$W/x" && tar -xzf "$W/tag.tar.gz" -C "$W/x" --no-same-owner
mv "$W/x/HeadsetControl-$VERSION" "$W/headsetcontrol-$VERSION"
SRC=$W/headsetcontrol-$VERSION
GIT_TREE=$(cd "$SRC" && GIT_DIR=$W/idx git init -q --bare "$W/idx" && GIT_DIR=$W/idx GIT_WORK_TREE=$SRC git add -A -f . && GIT_DIR=$W/idx git write-tree)
[ "$GIT_TREE" = "$TREE" ] || { echo "the unpacked tree is $GIT_TREE, the recipe pins $TREE" >&2; exit 1; }
echo "tree $GIT_TREE is commit $COMMIT's"
tar --sort=name --format=gnu --mtime="@$(date -u -d "$MTIME" +%s)" --owner=0 --group=0 --numeric-owner -C "$W" -cf - "headsetcontrol-$VERSION" | xz -9e -T1 >"$OUT/headsetcontrol_$VERSION.orig.tar.xz"
sha256sum "$OUT/headsetcontrol_$VERSION.orig.tar.xz"
