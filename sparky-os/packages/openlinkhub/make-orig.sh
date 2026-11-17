#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# Makes the two upstream archives of openlinkhub 0.9.4, byte for byte the same each time, and the vendored modules' licence table.
# Run where Go and git are installed and the network is reachable (a disposable container): the package build itself reads no network.
#   openlinkhub_0.9.4.orig.tar.xz         the release tag's tree, pinned by its commit and by its git tree id
#   openlinkhub_0.9.4.orig-vendor.tar.xz  `go mod vendor` of that tree (a component of the 3.0 (quilt) source, unpacked in vendor/)
#   vendor-licences.tsv and vendor-licences/  one row per vendored module and the legal files themselves, from the module cache (go to debian/)
# Usage: make-orig.sh OUTDIR
set -euo pipefail
OUT=${1:?output folder}
VERSION=0.9.4
TAG_SHA256=c77b3f914afa0cb9a7bbd5079bfe7be379dddafd71897979db72fdbf2a7c19ff   # codeload tar.gz of refs/tags/0.9.4
COMMIT=a08204cf88fd373a0bbdbe1f4382e8c64024adca                                  # the tag is lightweight: it names this commit
TREE=5e14fe011058ab371880bad1699f2fda784f2625                                    # that commit's git tree
MTIME=2026-11-01T07:00:43Z                                                       # that commit's committer date
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/openlinkhub-orig.XXXXXX")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$OUT"
curl -fsSL "https://codeload.github.com/jurkovic-nikola/OpenLinkHub/tar.gz/refs/tags/$VERSION" -o "$W/tag.tar.gz"
echo "$TAG_SHA256  $W/tag.tar.gz" | sha256sum -c -
python3 - "$W/tag.tar.gz" "$COMMIT" <<'PY'
import sys, tarfile
comment = tarfile.open(sys.argv[1]).pax_headers.get('comment')
if comment != sys.argv[2]:
	sys.exit(f'the archive names commit {comment}, the recipe pins {sys.argv[2]}')
PY
mkdir "$W/x" && tar -xzf "$W/tag.tar.gz" -C "$W/x" --no-same-owner
mv "$W/x/OpenLinkHub-$VERSION" "$W/openlinkhub-$VERSION"
SRC=$W/openlinkhub-$VERSION
# the git tree id of the unpacked files must be the commit's: a changed, added or lost file stops here
GIT_TREE=$(cd "$SRC" && GIT_DIR=$W/idx git init -q --bare "$W/idx" && GIT_DIR=$W/idx GIT_WORK_TREE=$SRC git add -A -f . && GIT_DIR=$W/idx git write-tree)
[ "$GIT_TREE" = "$TREE" ] || { echo "the unpacked tree is $GIT_TREE, the recipe pins $TREE" >&2; exit 1; }
echo "tree $GIT_TREE is commit $COMMIT's"
tar_det() { tar --sort=name --format=gnu --mtime="@$(date -u -d "$MTIME" +%s)" --owner=0 --group=0 --numeric-owner "$@"; }
tar_det -C "$W" -cf - "openlinkhub-$VERSION" | xz -9e -T1 >"$OUT/openlinkhub_$VERSION.orig.tar.xz"
# the vendored modules: upstream's go.mod and go.sum stay as they are, checked before and after
export GOTOOLCHAIN=local GOFLAGS=-mod=readonly GOPATH=$W/gopath GOMODCACHE=$W/gopath/mod GOCACHE=$W/gocache GOPROXY=https://proxy.golang.org GONOSUMDB='*' GOFLAGS=-mod=readonly
(cd "$SRC" && sha256sum go.mod go.sum >"$W/go.sha256" && go mod download && go mod verify && go mod vendor && sha256sum -c "$W/go.sha256")
(cd "$SRC" && go version && grep -c . vendor/modules.txt)
rm -rf "$OUT/vendor-licences"; python3 "$HERE/tools/vendor-licences.py" "$SRC/vendor/modules.txt" "$GOMODCACHE" "$OUT/vendor-licences" >"$OUT/vendor-licences.tsv"
tar_det -C "$SRC/vendor" -cf - . | xz -9e -T1 >"$OUT/openlinkhub_$VERSION.orig-vendor.tar.xz"
echo "vendor tree: $(cd "$SRC/vendor" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
sha256sum "$OUT/openlinkhub_$VERSION.orig.tar.xz" "$OUT/openlinkhub_$VERSION.orig-vendor.tar.xz" "$OUT/vendor-licences.tsv"
