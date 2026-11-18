#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Makes the upstream archive of droidcam 2.1.7 (Dev47Apps' Linux client for the DroidCam phone app), byte for byte the same each time:
#   droidcam_2.1.7.orig.tar.xz   the release tag's tree, pinned by its commit and by its git tree id
# Usage: make-orig.sh OUTDIR   (needs curl, git, xz, python3 and the network; the package build itself reads none)
set -euo pipefail
umask 022
OUT=${1:?output folder}
VERSION=2.1.7
TAG_SHA256=77f40eae703ab91e65d81959521b600a2b11e508fc295efd5986f08c1acd1cdb   # codeload tar.gz of refs/tags/v2.1.7
COMMIT=c8a0cc97663d90fe427d2c623b202628f8e95a17                                  # the tag is lightweight: the tarball names this commit
TREE=3a5e767990a5f5f5981a75fcff24a06cb15ed18e                                    # that commit's own tree (the tag has no export-ignore)
MTIME=2026-10-29T23:13:53Z                                                       # that commit's committer date (2026-10-29T16:13:53-07:00)
W=$(mktemp -d "${TMPDIR:-/tmp}/droidcam-orig.XXXXXX")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$OUT"
curl -fsSL "https://codeload.github.com/dev47apps/droidcam-linux-client/tar.gz/refs/tags/v$VERSION" -o "$W/tag.tar.gz"
echo "$TAG_SHA256  $W/tag.tar.gz" | sha256sum -c -
python3 - "$W/tag.tar.gz" "$COMMIT" <<'PY'
import sys, tarfile
comment = tarfile.open(sys.argv[1]).pax_headers.get('comment')
if comment != sys.argv[2]:
	sys.exit(f'the archive names commit {comment}, the recipe pins {sys.argv[2]}')
PY
mkdir "$W/x" && tar -xzf "$W/tag.tar.gz" -C "$W/x" --no-same-owner
mv "$W/x/droidcam-linux-client-$VERSION" "$W/droidcam-$VERSION"
SRC=$W/droidcam-$VERSION
GIT_TREE=$(cd "$SRC" && GIT_DIR=$W/idx git init -q --bare "$W/idx" && GIT_DIR=$W/idx GIT_WORK_TREE=$SRC git add -A -f . && GIT_DIR=$W/idx git write-tree)
[ "$GIT_TREE" = "$TREE" ] || { echo "the unpacked tree is $GIT_TREE, the recipe pins $TREE" >&2; exit 1; }
echo "tree $GIT_TREE is commit $COMMIT's"
tar --sort=name --format=gnu --mtime="@$(date -u -d "$MTIME" +%s)" --owner=0 --group=0 --numeric-owner -C "$W" -cf - "droidcam-$VERSION" | xz -9e -T1 >"$OUT/droidcam_$VERSION.orig.tar.xz"
sha256sum "$OUT/droidcam_$VERSION.orig.tar.xz"
