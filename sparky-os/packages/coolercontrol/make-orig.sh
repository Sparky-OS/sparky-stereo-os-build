#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Makes the upstream archives of coolercontrol 5.1.2, byte for byte the same each time, and the licence tables. Run where nodejs, npm, cargo, rustc, git, patch
# and curl are installed and the network is reachable (a disposable container): the package build reads no network.
#   coolercontrol_5.1.2.orig.tar.xz               the release tag's tree (tarball SHA-256, commit and git tree id pinned below)
#   coolercontrol_5.1.2.orig-vendor.tar.xz        `cargo vendor --locked` of the daemon's workspace (unpacked in coolercontrold/vendor)
#   coolercontrol_5.1.2.orig-npm.tar.xz           node_modules of the interface, installed from package-lock.json AS CHANGED BY debian/patches/0001 (npm ci
#                                                 --ignore-scripts --omit=optional: no prebuilt native package of esbuild or Rollup is installed); npm checks every
#                                                 tarball against the lock's integrity hash
#   coolercontrol_5.1.2.orig-rollup.tar.xz        Rollup 4.68.6's rust/ workspace, the source of the native part the interface's bundler needs
#   coolercontrol_5.1.2.orig-rollupvendor.tar.xz  `cargo vendor --locked` of that workspace
#   crate-licences.tsv, rollup-crate-licences.tsv, npm-licences.tsv, the legal files (out of git), cargo-config.toml, rollup-cargo-config.toml
# Usage: make-orig.sh OUTDIR
set -euo pipefail
umask 022
OUT=${1:?output folder}
VERSION=5.1.2
TAG_SHA256=578d9dac425f3184f5c3fcf29a1a1d0b80c45a24c6d9c47cd316abc80f84a324   # gitlab.com/coolercontrol/coolercontrol/-/archive/5.1.2/coolercontrol-5.1.2.tar.gz
COMMIT=b4ba6db3e0b87dc4835492a2bada87b2b8163743                              # the tag's commit (the archive's pax header names it)
TREE=15b0ed7fb171280a0690b8b1254e33cf59dc0e75                                                                # the unpacked tarball's git tree
MTIME=2026-11-12T00:00:00Z                                                   # a fixed date for every archive member
ROLLUP=4.68.6
ROLLUP_SHA256=37b425b2af91b894674eeec5386c31ef2970ebe6608208d60c2f2f06e7bb6b7e   # codeload.github.com/rollup/rollup/tar.gz/refs/tags/v4.68.6
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d "${TMPDIR:-/tmp}/cc-orig.XXXXXX")
trap 'chmod -R u+w "$W" 2>/dev/null; rm -rf "$W"' EXIT
mkdir -p "$OUT"
tar_det() { tar --sort=name --format=gnu --mtime="@$(date -u -d "$MTIME" +%s)" --owner=0 --group=0 --numeric-owner "$@"; }
export CARGO_HOME=$W/cargo CARGO_NET_GIT_FETCH_WITH_CLI=true
# 1. the tag's tree
curl -fsSL "https://gitlab.com/coolercontrol/coolercontrol/-/archive/$VERSION/coolercontrol-$VERSION.tar.gz" -o "$W/tag.tar.gz"
echo "$TAG_SHA256  $W/tag.tar.gz" | sha256sum -c -
python3 - "$W/tag.tar.gz" "$COMMIT" <<'PY'
import sys, tarfile
comment = tarfile.open(sys.argv[1]).pax_headers.get('comment')
if comment != sys.argv[2]:
	sys.exit(f'the archive names commit {comment}, the recipe pins {sys.argv[2]}')
PY
mkdir "$W/x" && tar -xzf "$W/tag.tar.gz" -C "$W/x" --no-same-owner
mv "$W/x/coolercontrol-$VERSION" "$W/coolercontrol-$VERSION"
SRC=$W/coolercontrol-$VERSION
GIT_TREE=$(cd "$SRC" && GIT_DIR=$W/idx git init -q --bare "$W/idx" && GIT_DIR=$W/idx GIT_WORK_TREE=$SRC git add -A -f . && GIT_DIR=$W/idx git write-tree)
if [ "$TREE" = "@@TREE@@" ]; then echo "tree $GIT_TREE (pin it as TREE)"; elif [ "$GIT_TREE" != "$TREE" ]; then echo "the unpacked tree is $GIT_TREE, the recipe pins $TREE" >&2; exit 1; fi
tar_det -C "$W" -cf - "coolercontrol-$VERSION" | xz -9e -T1 >"$OUT/coolercontrol_$VERSION.orig.tar.xz"
# 2. the daemon's crates; Cargo.toml and Cargo.lock stay as they are, checked before and after
(cd "$SRC/coolercontrold" && sha256sum Cargo.toml Cargo.lock >"$W/cargo.sha256" && cargo --version && cargo vendor --locked vendor >"$W/vendor-config.raw" && sha256sum -c "$W/cargo.sha256")
sed 's|^directory = .*|directory = "vendor"|' "$W/vendor-config.raw" >"$OUT/cargo-config.toml"
rm -rf "$OUT/crate-licences"; python3 "$HERE/tools/crate-licences.py" "$SRC/coolercontrold/vendor" "$OUT/crate-licences" >"$OUT/crate-licences.tsv"
tar_det -C "$SRC/coolercontrold/vendor" -cf - . | xz -9e -T1 >"$OUT/coolercontrol_$VERSION.orig-vendor.tar.xz"
echo "daemon vendor tree: $(cd "$SRC/coolercontrold/vendor" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
# 3. the interface's node_modules, from the lock the patch changes
(cd "$SRC" && patch -p1 <"$HERE/debian/patches/0001-ui-build-chain-vite7-rollup-esbuild.patch" >"$W/patch.log")
UI=$SRC/coolercontrol-ui
(cd "$UI" && sha256sum package-lock.json >"$W/lock.sha256" && npm ci --ignore-scripts --omit=optional --no-audit --no-fund >"$W/npm.log" 2>&1 && sha256sum -c "$W/lock.sha256")
# a prebuilt WebAssembly file of editorconfig's parser (js-beautify, a developer tool the interface's build does not load): the build passes without it, so it is not carried
rm -rf "$UI/node_modules/@one-ini"
# no prebuilt object may be left in the tree
find "$UI/node_modules" -type f \( -name '*.node' -o -name '*.wasm' \) -print | tee "$W/natives.txt"
[ ! -s "$W/natives.txt" ] || { echo "prebuilt objects in the npm tree" >&2; exit 1; }
find "$UI/node_modules" -type f -perm -u+x -exec sh -c 'head -c4 "$1" | grep -q ELF && echo "ELF $1"' _ {} \; | tee "$W/elf.txt"
[ ! -s "$W/elf.txt" ] || { echo "executables in the npm tree" >&2; exit 1; }
rm -rf "$OUT/npm-legal"; python3 "$HERE/tools/npm-licences.py" "$UI/node_modules" "$OUT/npm-legal" >"$OUT/npm-licences.tsv"
tar_det -C "$UI/node_modules" -cf - . | xz -9e -T1 >"$OUT/coolercontrol_$VERSION.orig-npm.tar.xz"
echo "npm tree: $(cd "$UI/node_modules" && find . \( -type f -o -type l \) -print0 | LC_ALL=C sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)"
# 4. Rollup's native part: the rust/ workspace of the tag the interface's Rollup (lock: 4.68.6) comes from
grep -q "\"version\": \"$ROLLUP\"" "$UI/node_modules/rollup/package.json" || { echo "the lock's rollup is not $ROLLUP" >&2; exit 1; }
curl -fsSL "https://codeload.github.com/rollup/rollup/tar.gz/refs/tags/v$ROLLUP" -o "$W/rollup.tar.gz"
echo "$ROLLUP_SHA256  $W/rollup.tar.gz" | sha256sum -c -
mkdir "$W/r" && tar -xzf "$W/rollup.tar.gz" -C "$W/r" --no-same-owner
mkdir "$W/rollup-$ROLLUP" && cp -a "$W/r/rollup-$ROLLUP/rust" "$W/r/rollup-$ROLLUP/LICENSE.md" "$W/rollup-$ROLLUP/"
(cd "$W/rollup-$ROLLUP/rust" && sha256sum Cargo.toml Cargo.lock >"$W/rcargo.sha256" && cargo vendor --locked vendor >"$W/rvendor-config.raw" && sha256sum -c "$W/rcargo.sha256")
sed 's|^directory = .*|directory = "vendor"|' "$W/rvendor-config.raw" >"$OUT/rollup-cargo-config.toml"
rm -rf "$OUT/rollup-crate-licences"; python3 "$HERE/tools/crate-licences.py" "$W/rollup-$ROLLUP/rust/vendor" "$OUT/rollup-crate-licences" >"$OUT/rollup-crate-licences.tsv"
mv "$W/rollup-$ROLLUP/rust/vendor" "$W/rvendor"
tar_det -C "$W" -cf - "rollup-$ROLLUP" | xz -9e -T1 >"$OUT/coolercontrol_$VERSION.orig-rollup.tar.xz"
tar_det -C "$W/rvendor" -cf - . | xz -9e -T1 >"$OUT/coolercontrol_$VERSION.orig-rollupvendor.tar.xz"
echo "rollup vendor tree: $(cd "$W/rvendor" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
(cd "$OUT" && sha256sum coolercontrol_$VERSION.orig*.tar.xz *.tsv cargo-config.toml rollup-cargo-config.toml)
