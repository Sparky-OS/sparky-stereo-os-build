#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: CoolerControl 5.1.2 (the daemon, its interface and the Qt window) built from the release tag's source through the Lean Code
# toolkit (release/build-dh-lean.sh), by the route of go-release-packaging.md and npm-vendored-packaging.md: the source package has five upstream
# tarballs made by make-orig.sh, each checked before it is used,
#   coolercontrol_V.orig.tar.xz            the tag's tree (tarball SHA-256, commit and git tree id pinned in make-orig.sh)
#   coolercontrol_V.orig-vendor.tar.xz     the daemon's crates, Cargo.toml and Cargo.lock unchanged            -> vendor/
#   coolercontrol_V.orig-npm.tar.xz        the interface's node_modules, from the lock the patch changes      -> npm/
#   coolercontrol_V.orig-rollup.tar.xz     Rollup 4.68.6's rust/ workspace                                    -> rollup/
#   coolercontrol_V.orig-rollupvendor.tar.xz  its crates                                                       -> rollupvendor/
# so the package build reads no network. debian/ is the tracked one at PACKAGING_COMMIT of CLONE, never the work tree; the legal files of the crates and of
# the npm packages (they carry their authors' addresses) come from the trees and must be the files the three debian/*licences.tsv tables pin by hash.
# Usage: build.sh OUT CLONE [PACKAGING_COMMIT]   (OUT an empty folder; CLONE the edition's build repository)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?empty output folder}")
CLONE=$(realpath "${2:?clone of the build repository}")
PACKAGING_COMMIT=$(git -C "$CLONE" rev-parse --verify "${3:-HEAD}^{commit}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
UPV=5.1.2
# sha256 of the sorted `sha256sum` list of every file of each tree (make-orig.sh prints them)
VENDOR_SHA256=c9f84b4034d8eeef7e9672491737b516b6e90f8e13910fcd5d28a83c4c6f4574
ROLLUPVENDOR_SHA256=6d38d2ced8ff11cf30d752341d628adc58051ca6668de9abe6fa3ec0ddc67d32
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
git -C "$CLONE" diff --quiet "$PACKAGING_COMMIT" -- sparky-os/packages/coolercontrol || { echo "the recipe in $CLONE differs from $PACKAGING_COMMIT: commit first" >&2; exit 1; }
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/coolercontrol.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
SRC=coolercontrol-$UPV
mkdir "$WORK/orig"
if [ -n "${ORIG_CACHE:-}" ] && [ -f "$ORIG_CACHE/coolercontrol_$UPV.orig-npm.tar.xz" ]; then
	# archives an earlier run of make-orig.sh made (a rebuild need not fetch and compress them again); the checks below still apply
	cp "$ORIG_CACHE"/coolercontrol_"$UPV".orig*.tar.xz "$ORIG_CACHE"/*.tsv "$ORIG_CACHE"/cargo-config.toml "$ORIG_CACHE"/rollup-cargo-config.toml "$WORK/orig/"
	cp -a "$ORIG_CACHE/crate-licences" "$ORIG_CACHE/rollup-crate-licences" "$ORIG_CACHE/npm-legal" "$WORK/orig/"
else
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}coolercontrol-orig" --platform linux/amd64 --cpus "${CPUS:-4}" --ulimit core=1 \
	-v "$WORK/orig":/out -v "$HERE":/pkg:ro -e OWNER="$(id -u):$(id -g)" \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMAGE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install nodejs npm cargo rustc cmake git patch ca-certificates curl xz-utils python3 >/dev/null
useradd --create-home --uid 1000 builder
chown builder:builder /out
runuser -u builder -- env HOME=/tmp/builder-home bash /pkg/make-orig.sh /out
chown -R "$OWNER" /out'
fi
tar -xJf "$WORK/orig/coolercontrol_$UPV.orig.tar.xz" -C "$WORK"
unpack() { mkdir "$WORK/$SRC/$2"; tar -xJf "$WORK/orig/coolercontrol_$UPV.orig-$1.tar.xz" -C "$WORK/$SRC/$2"; }
unpack vendor vendor; unpack npm npm; unpack rollupvendor rollupvendor
# the rollup archive holds one folder (rollup-V): dpkg-source strips it, so does this
mkdir "$WORK/$SRC/rollup"; tar -xJf "$WORK/orig/coolercontrol_$UPV.orig-rollup.tar.xz" -C "$WORK/$SRC/rollup" --strip-components=1
fp() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1); }
[ "$(fp "$WORK/$SRC/vendor")" = "$VENDOR_SHA256" ] || { echo "vendor tree is $(fp "$WORK/$SRC/vendor"), not $VENDOR_SHA256" >&2; exit 1; }
[ "$(fp "$WORK/$SRC/rollupvendor")" = "$ROLLUPVENDOR_SHA256" ] || { echo "rollupvendor tree is $(fp "$WORK/$SRC/rollupvendor"), not $ROLLUPVENDOR_SHA256" >&2; exit 1; }
cp "$WORK"/orig/coolercontrol_"$UPV".orig*.tar.xz "$WORK"/
git -C "$CLONE" archive --format=tar "$PACKAGING_COMMIT" sparky-os/packages/coolercontrol/debian | tar -x -C "$WORK/$SRC" --strip-components=3
echo "packaging: $PACKAGING_COMMIT"
for t in crate-licences.tsv rollup-crate-licences.tsv npm-licences.tsv; do
	cmp "$WORK/orig/$t" "$WORK/$SRC/debian/$t" || { echo "debian/$t is not what make-orig.sh gives for these trees" >&2; exit 1; }
done
cmp "$WORK/orig/cargo-config.toml" "$WORK/$SRC/debian/cargo-config.toml" || { echo "debian/cargo-config.toml is not what cargo vendor gave" >&2; exit 1; }
cmp "$WORK/orig/rollup-cargo-config.toml" "$WORK/$SRC/debian/rollup-cargo-config.toml" || { echo "debian/rollup-cargo-config.toml is not what cargo vendor gave" >&2; exit 1; }
# the legal texts are not kept in git: they come from the trees and must be the files the tables pin, none extra, none missing
mkdir "$WORK/$SRC/debian/vendor-licences"
cp -a "$WORK/orig/crate-licences" "$WORK/$SRC/debian/vendor-licences/daemon-crates"
cp -a "$WORK/orig/rollup-crate-licences" "$WORK/$SRC/debian/vendor-licences/rollup-crates"
cp -a "$WORK/orig/npm-legal" "$WORK/$SRC/debian/vendor-licences/npm"
python3 - "$WORK/$SRC/debian" <<'PY'
import csv, hashlib, os, sys
d = sys.argv[1]
total = 0
for table, sub in (('crate-licences.tsv', 'daemon-crates'), ('rollup-crate-licences.tsv', 'rollup-crates'), ('npm-licences.tsv', 'npm')):
	root = os.path.join(d, 'vendor-licences', sub)
	want = {}
	for row in csv.reader(open(os.path.join(d, table), encoding='utf-8'), delimiter='\t'):
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
		sys.exit(f'debian/vendor-licences/{sub} does not match debian/{table}:\n  ' + '\n  '.join(problems[:20]))
	total += len(want)
print(f'{total} legal files match the pinned hashes')
PY
DEBV=$(dpkg-parsechangelog -l "$WORK/$SRC/debian/changelog" -S Version)
[ "${DEBV%-*}" = "$UPV" ] || { echo "debian/changelog is $DEBV, not $UPV" >&2; exit 1; }
rm -rf "$WORK/orig"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "$SRC" "$DEBV+lc1" "$REPO"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
