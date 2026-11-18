#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Makes the two upstream archives of lact 0.10.1, byte for byte the same each time, and the crates' licence table.
# Run where cargo, rustc and git are installed and the network is reachable (a disposable container): the package build reads no network.
#   lact_0.10.1.orig.tar.xz         the release tag's tree, pinned by its commit and by its git tree id
#   lact_0.10.1.orig-vendor.tar.xz  `cargo vendor --locked` of that tree (a component of the 3.0 (quilt) source, unpacked in vendor/)
#   crate-licences.tsv, crate-licences/, cargo-config.toml   the licence table, the legal files, cargo's source replacement
# Usage: make-orig.sh OUTDIR
set -euo pipefail
umask 022
OUT=${1:?output folder}
VERSION=0.10.1
TAG_SHA256=cbbbd0336fb65ce539ea29d99fe2e38f7c82de08c07d26dfab355735a88d853c   # codeload tar.gz of refs/tags/v0.10.1
COMMIT=30dc182391e2c002f6f7c988e76aa477a4772aa2                                  # the tag is lightweight: it names this commit
TREE=db82ba79c61c8fc27fb84fcb201de9a5bd80f229                                    # that commit's git tree
MTIME=2026-08-29T14:56:05Z                                                       # that commit's committer date
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/lact-orig.XXXXXX")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$OUT"
curl -fsSL "https://codeload.github.com/ilya-zlobintsev/LACT/tar.gz/refs/tags/v$VERSION" -o "$W/tag.tar.gz"
echo "$TAG_SHA256  $W/tag.tar.gz" | sha256sum -c -
python3 - "$W/tag.tar.gz" "$COMMIT" <<'PY'
import sys, tarfile
comment = tarfile.open(sys.argv[1]).pax_headers.get('comment')
if comment != sys.argv[2]:
	sys.exit(f'the archive names commit {comment}, the recipe pins {sys.argv[2]}')
PY
mkdir "$W/x" && tar -xzf "$W/tag.tar.gz" -C "$W/x" --no-same-owner
mv "$W/x/LACT-$VERSION" "$W/lact-$VERSION"
SRC=$W/lact-$VERSION
GIT_TREE=$(cd "$SRC" && GIT_DIR=$W/idx git init -q --bare "$W/idx" && GIT_DIR=$W/idx GIT_WORK_TREE=$SRC git add -A -f . && GIT_DIR=$W/idx git write-tree)
[ "$GIT_TREE" = "$TREE" ] || { echo "the unpacked tree is $GIT_TREE, the recipe pins $TREE" >&2; exit 1; }
echo "tree $GIT_TREE is commit $COMMIT's"
tar_det() { tar --sort=name --format=gnu --mtime="@$(date -u -d "$MTIME" +%s)" --owner=0 --group=0 --numeric-owner "$@"; }
tar_det -C "$W" -cf - "lact-$VERSION" | xz -9e -T1 >"$OUT/lact_$VERSION.orig.tar.xz"
# upstream's Cargo.toml and Cargo.lock stay as they are, checked before and after; rust-toolchain.toml names a rustup channel Debian's cargo ignores
export CARGO_HOME=$W/cargo CARGO_NET_GIT_FETCH_WITH_CLI=true
(cd "$SRC" && sha256sum Cargo.toml Cargo.lock >"$W/cargo.sha256" && cargo --version && cargo vendor --locked vendor >"$W/vendor-config.raw" && sha256sum -c "$W/cargo.sha256")
sed 's|^directory = .*|directory = "vendor"|' "$W/vendor-config.raw" >"$OUT/cargo-config.toml"
rm -rf "$OUT/crate-licences"; python3 "$HERE/tools/crate-licences.py" "$SRC/vendor" "$OUT/crate-licences" >"$OUT/crate-licences.tsv"
tar_det -C "$SRC/vendor" -cf - . | xz -9e -T1 >"$OUT/lact_$VERSION.orig-vendor.tar.xz"
echo "vendor tree: $(cd "$SRC/vendor" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
sha256sum "$OUT/lact_$VERSION.orig.tar.xz" "$OUT/lact_$VERSION.orig-vendor.tar.xz" "$OUT/crate-licences.tsv" "$OUT/cargo-config.toml"
