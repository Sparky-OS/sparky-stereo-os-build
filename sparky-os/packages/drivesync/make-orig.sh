#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/27
# Copyright 2026 under the GNU GPL3 License
# Makes the two upstream archives of DriveSync 0.1.0+git20261126.082e743, byte for byte the same each time, and the
# crates' licence table. DriveSync has no release or tag yet: the source is one commit of its default branch, pinned by
# the codeload archive's SHA-256, the commit the archive's pax header names and that commit's git tree id.
# Run where cargo, rustc, git and patch are installed and the network is reachable (a disposable container): the
# package build reads no network.
#   drivesync_V.orig.tar.xz         the commit's tree, unchanged
#   drivesync_V.orig-vendor.tar.xz  `cargo vendor --locked` of that tree with debian/patches applied (0002 moves reqwest
#                                   to the system certificate store, which adds rustls-native-certs to Cargo.lock)
#   crate-licences.tsv, crate-licences/, cargo-config.toml   the licence table, the legal files, cargo's source replacement
# Usage: make-orig.sh OUTDIR
set -euo pipefail
umask 022
OUT=${1:?output folder}
VERSION=0.1.0+git20261126.082e743
COMMIT=082e743ac3eb6755cb4970f768491335281adffa                                  # rafatosta/drivesync main, 2026-11-26 01:45 UTC
TAR_SHA256=4da608d2a2f88dd590545464d65e438022389707350dd715b950e84fa0cb8c58   # codeload tar.gz of that commit
TREE=78313f02941ac75dd4b6b993923eb09fcbcb5e22                                    # that commit's git tree
MTIME=2026-11-26T01:45:00Z                                                       # that commit's committer date
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/drivesync-orig.XXXXXX")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$OUT"
curl -fsSL "https://codeload.github.com/rafatosta/drivesync/tar.gz/$COMMIT" -o "$W/src.tar.gz"
echo "$TAR_SHA256  $W/src.tar.gz" | sha256sum -c -
python3 -I - "$W/src.tar.gz" "$COMMIT" <<'PY'
import sys, tarfile
comment = tarfile.open(sys.argv[1]).pax_headers.get('comment')
if comment != sys.argv[2]:
	sys.exit(f'the archive names commit {comment}, the recipe pins {sys.argv[2]}')
PY
mkdir "$W/x" && tar -xzf "$W/src.tar.gz" -C "$W/x" --no-same-owner
mv "$W/x/drivesync-$COMMIT" "$W/drivesync-$VERSION"
SRC=$W/drivesync-$VERSION
GIT_TREE=$(cd "$SRC" && GIT_DIR=$W/idx git init -q --bare "$W/idx" && GIT_DIR=$W/idx GIT_WORK_TREE=$SRC git add -A -f . && GIT_DIR=$W/idx git write-tree)
[ "$GIT_TREE" = "$TREE" ] || { echo "the unpacked tree is $GIT_TREE, the recipe pins $TREE" >&2; exit 1; }
echo "tree $GIT_TREE is commit $COMMIT's"
tar_det() { tar --sort=name --format=gnu --mtime="@$(date -u -d "$MTIME" +%s)" --owner=0 --group=0 --numeric-owner "$@"; }
tar_det -C "$W" -cf - "drivesync-$VERSION" | xz -9e -T1 >"$OUT/drivesync_$VERSION.orig.tar.xz"
# the crates come from the patched Cargo.toml and Cargo.lock, the ones the package builds; both are checked unchanged by cargo
cp -a "$SRC" "$W/patched"
while read -r patch; do
	[ -n "$patch" ] && patch -s -p1 -d "$W/patched" <"$HERE/debian/patches/$patch"
done <"$HERE/debian/patches/series"
export CARGO_HOME=$W/cargo CARGO_NET_GIT_FETCH_WITH_CLI=true
(cd "$W/patched" && sha256sum Cargo.toml Cargo.lock engine/Cargo.toml >"$W/cargo.sha256" && cargo --version && cargo vendor --locked vendor >"$W/vendor-config.raw" && sha256sum -c "$W/cargo.sha256")
sed 's|^directory = .*|directory = "vendor"|' "$W/vendor-config.raw" >"$OUT/cargo-config.toml"
rm -rf "$OUT/crate-licences"; python3 -I "$HERE/tools/crate-licences.py" "$W/patched/vendor" "$OUT/crate-licences" >"$OUT/crate-licences.tsv"
tar_det -C "$W/patched/vendor" -cf - . | xz -9e -T1 >"$OUT/drivesync_$VERSION.orig-vendor.tar.xz"
echo "vendor tree: $(cd "$W/patched/vendor" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
sha256sum "$OUT/drivesync_$VERSION.orig.tar.xz" "$OUT/drivesync_$VERSION.orig-vendor.tar.xz" "$OUT/crate-licences.tsv" "$OUT/cargo-config.toml"
