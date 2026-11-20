#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/20
# Copyright 2026 under the GNU GPL3 License
# Makes the upstream archive of katemark 0.4.7, byte for byte the same each time:
#   katemark_0.4.7.orig.tar.xz   the release tag's tree, pinned by its commit and by its git tree id
# Usage: make-orig.sh OUTDIR   (needs curl, git, xz, python3 and the network over https; the package build itself reads none)
set -euo pipefail
umask 022
OUT=${1:?output folder}
VERSION=0.4.7
TAG_SHA256=b20c71d771af872c181ef1d03560d94f16a6bf22ddf874ffa08dcd8a595beec1   # codeload tar.gz of refs/tags/v0.4.7
COMMIT=9b9a0505b13099ff7f485b630d38b2915c3dfab7                                 # the archive names this commit (tarball comment)
TREE=42743438bffd8c18a9c39141c9070619c5869ea9                                   # the commit's own tree, the archive's tree is the same
MTIME=2026-11-08T21:51:15Z                                                      # that commit's date
W=$(mktemp -d "${TMPDIR:-/tmp}/katemark-orig.XXXXXX")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$OUT"
curl -fsSL "https://codeload.github.com/obook/katemark/tar.gz/refs/tags/v$VERSION" -o "$W/tag.tar.gz"
echo "$TAG_SHA256  $W/tag.tar.gz" | sha256sum -c -
python3 - "$W/tag.tar.gz" "$COMMIT" <<'PY'
import sys, tarfile
comment = tarfile.open(sys.argv[1]).pax_headers.get('comment')
if comment != sys.argv[2]:
	sys.exit(f'the archive names commit {comment}, the recipe pins {sys.argv[2]}')
PY
mkdir "$W/x" && tar -xzf "$W/tag.tar.gz" -C "$W/x" --no-same-owner
mv "$W/x/katemark-$VERSION" "$W/katemark-$VERSION"
SRC=$W/katemark-$VERSION
GIT_TREE=$(cd "$SRC" && GIT_DIR=$W/idx git init -q --bare "$W/idx" && GIT_DIR=$W/idx GIT_WORK_TREE=$SRC git add -A -f . && GIT_DIR=$W/idx git write-tree)
[ "$GIT_TREE" = "$TREE" ] || { echo "the unpacked tree is $GIT_TREE, the recipe pins $TREE" >&2; exit 1; }
echo "tree $GIT_TREE is commit $COMMIT's"
tar --sort=name --format=gnu --mtime="@$(date -u -d "$MTIME" +%s)" --owner=0 --group=0 --numeric-owner -C "$W" -cf - "katemark-$VERSION" | xz -9e -T1 >"$OUT/katemark_$VERSION.orig.tar.xz"
sha256sum "$OUT/katemark_$VERSION.orig.tar.xz"
