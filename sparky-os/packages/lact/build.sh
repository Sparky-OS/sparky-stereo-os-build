#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: LACT 0.10.1 (Ilya Zlobintsev's graphics card control, Rust with GTK 4) built from the release tag's source through the
# Lean Code toolkit (release/build-dh-lean.sh), by the route of go-release-packaging.md for a vendored build: the source package has two
# upstream tarballs made by make-orig.sh, each checked before it is used,
#   lact_V.orig.tar.xz          the tag's tree (tarball SHA-256, commit and git tree id pinned in make-orig.sh)
#   lact_V.orig-vendor.tar.xz   the crates Cargo.lock names, Cargo.toml and Cargo.lock left unchanged
# so the package build reads no network. debian/ is the tracked one at PACKAGING_COMMIT of CLONE, never the work tree; the crates' legal
# files (they carry their authors' addresses) come from the vendor tree and must be the files debian/crate-licences.tsv pins by hash.
# Usage: build.sh OUT CLONE [PACKAGING_COMMIT]   (OUT an empty folder; CLONE the edition's build repository)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?empty output folder}")
CLONE=$(realpath "${2:?clone of the build repository}")
PACKAGING_COMMIT=$(git -C "$CLONE" rev-parse --verify "${3:-HEAD}^{commit}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
UPV=0.10.1
# sha256 of the sorted `sha256sum` list of every file under vendor/ (make-orig.sh prints it)
VENDOR_SHA256=931e7127c66e2a176634584cb7ba0da136e1199af7d9bd0bfb692f5d6525c930
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
git -C "$CLONE" diff --quiet "$PACKAGING_COMMIT" -- sparky-os/packages/lact || { echo "the recipe in $CLONE differs from $PACKAGING_COMMIT: commit first" >&2; exit 1; }
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/lact.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
SRC=lact-$UPV
mkdir "$WORK/orig"
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}lact-orig" --platform linux/amd64 --cpus "${CPUS:-4}" --ulimit core=0 \
	-v "$WORK/orig":/out -v "$HERE":/pkg:ro -e OWNER="$(id -u):$(id -g)" \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMAGE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install cargo rustc git ca-certificates curl xz-utils python3 >/dev/null
useradd --create-home --uid 1000 builder
chown builder:builder /out
runuser -u builder -- env HOME=/tmp/builder-home bash /pkg/make-orig.sh /out
chown -R "$OWNER" /out'
tar -xJf "$WORK/orig/lact_$UPV.orig.tar.xz" -C "$WORK"
mkdir "$WORK/$SRC/vendor"
tar -xJf "$WORK/orig/lact_$UPV.orig-vendor.tar.xz" -C "$WORK/$SRC/vendor"
got=$(cd "$WORK/$SRC/vendor" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
[ "$got" = "$VENDOR_SHA256" ] || { echo "vendor tree is $got, not $VENDOR_SHA256" >&2; exit 1; }
cp "$WORK"/orig/lact_"$UPV".orig*.tar.xz "$WORK"/
git -C "$CLONE" archive --format=tar "$PACKAGING_COMMIT" sparky-os/packages/lact/debian | tar -x -C "$WORK/$SRC" --strip-components=3
echo "packaging: $PACKAGING_COMMIT"
cmp "$WORK/orig/crate-licences.tsv" "$WORK/$SRC/debian/crate-licences.tsv" || { echo "debian/crate-licences.tsv is not what make-orig.sh gives for these crates" >&2; exit 1; }
cmp "$WORK/orig/cargo-config.toml" "$WORK/$SRC/debian/cargo-config.toml" || { echo "debian/cargo-config.toml is not what cargo vendor gave" >&2; exit 1; }
# the legal texts are not kept in git: they come from the vendor tree and must be the files the table pins, none extra, none missing
cp -a "$WORK/orig/crate-licences" "$WORK/$SRC/debian/vendor-licences"
python3 - "$WORK/$SRC/debian/crate-licences.tsv" "$WORK/$SRC/debian/vendor-licences" <<'PY'
import csv, hashlib, os, sys
table, root = sys.argv[1:3]
want = {}
for row in csv.reader(open(table, encoding='utf-8'), delimiter='\t'):
	if not row or row[0].startswith('#') or not row[3]:
		continue
	for item in row[3].split(';'):
		path, _, digest = item.rpartition(':')
		want[os.path.join(row[0], path)] = digest
have = {}
for base, _, files in os.walk(root):
	for name in files:
		full = os.path.join(base, name)
		have[os.path.relpath(full, root)] = hashlib.sha256(open(full, 'rb').read()).hexdigest()
problems = [f'missing {p}' for p in sorted(want.keys() - have.keys())] + [f'extra {p}' for p in sorted(have.keys() - want.keys())]
problems += [f'{p}: sha256 {have[p]} is not the pinned {want[p]}' for p in sorted(want.keys() & have.keys()) if want[p] != have[p]]
if problems:
	sys.exit('debian/vendor-licences does not match debian/crate-licences.tsv:\n  ' + '\n  '.join(problems[:20]))
print(f'{len(want)} legal files match the pinned hashes')
PY
DEBV=$(dpkg-parsechangelog -l "$WORK/$SRC/debian/changelog" -S Version)
[ "${DEBV%-*}" = "$UPV" ] || { echo "debian/changelog is $DEBV, not $UPV" >&2; exit 1; }
rm -rf "$WORK/orig"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "$SRC" "$DEBV+lc1" "$REPO"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
