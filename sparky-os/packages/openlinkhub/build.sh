#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# Sparky Stereo OS: OpenLinkHub 0.9.4 (Nikola Jurkovic's interface for Corsair iCUE LINK hubs, coolers, lighting nodes and power
# supplies, in Go with cgo) built from the release tag's source through the Lean Code toolkit (release/build-dh-lean.sh), by the
# route of go-release-packaging.md: the source package has two upstream tarballs made by make-orig.sh, each checked before it is used,
#   openlinkhub_V.orig.tar.xz          the tag's tree (tarball SHA-256, commit and git tree id pinned in make-orig.sh)
#   openlinkhub_V.orig-vendor.tar.xz   the modules go.mod and go.sum name, verified against go.sum, both left unchanged
# so the package build reads no network (GOPROXY=off, -mod=vendor, GOTOOLCHAIN=local). debian/ is the tracked one at PACKAGING_COMMIT of
# CLONE, never the work tree. Usage: build.sh OUT CLONE [PACKAGING_COMMIT]   (OUT an empty folder; CLONE the edition's build repository;
# the commit by default CLONE's HEAD). SPARKY_SCRATCH, REPO, IMAGE, SPARKY_LC_ARCHIVE_DIR as release/build-dh-lean.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:?empty output folder}")
CLONE=$(realpath "${2:?clone of the build repository}")
PACKAGING_COMMIT=$(git -C "$CLONE" rev-parse --verify "${3:-HEAD}^{commit}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
IMAGE=${IMAGE:-sparky-lc-migration:20261020}
UPV=0.9.4
# sha256 of the sorted `sha256sum` list of every file under vendor/ (make-orig.sh prints it)
VENDOR_SHA256=ee3c176f88c392b5830a26df39547bc8b80e51f46a43ce2177f86490272062ac
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
git -C "$CLONE" diff --quiet "$PACKAGING_COMMIT" -- sparky-os/packages/openlinkhub || { echo "the recipe in $CLONE differs from $PACKAGING_COMMIT: commit first" >&2; exit 1; }
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/openlinkhub.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
SRC=openlinkhub-$UPV
mkdir "$WORK/orig"
# the one step that reads the network, in a container
docker run --rm --name "${SPARKY_CONTAINER_PREFIX:+$SPARKY_CONTAINER_PREFIX-}openlinkhub-orig" --platform linux/amd64 --cpus "${CPUS:-4}" --ulimit core=1 \
	-v "$WORK/orig":/out -v "$HERE":/pkg:ro -e OWNER="$(id -u):$(id -g)" \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMAGE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/dev/null
apt-get -y --no-install-recommends install golang-go git ca-certificates curl xz-utils python3 >/dev/null
useradd --create-home --uid 1000 builder
chown builder:builder /out
runuser -u builder -- env HOME=/tmp/builder-home bash /pkg/make-orig.sh /out
chown -R "$OWNER" /out'
tar -xJf "$WORK/orig/openlinkhub_$UPV.orig.tar.xz" -C "$WORK"
mkdir "$WORK/$SRC/vendor"
tar -xJf "$WORK/orig/openlinkhub_$UPV.orig-vendor.tar.xz" -C "$WORK/$SRC/vendor"
got=$(cd "$WORK/$SRC/vendor" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
[ "$got" = "$VENDOR_SHA256" ] || { echo "vendor tree is $got, not $VENDOR_SHA256" >&2; exit 1; }
cp "$WORK"/orig/openlinkhub_"$UPV".orig*.tar.xz "$WORK"/
# the packaging: only the tracked debian/ at the commit
git -C "$CLONE" archive --format=tar "$PACKAGING_COMMIT" sparky-os/packages/openlinkhub/debian | tar -x -C "$WORK/$SRC" --strip-components=3
echo "packaging: $PACKAGING_COMMIT"
cmp "$WORK/orig/vendor-licences.tsv" "$WORK/$SRC/debian/vendor-licences.tsv" || { echo "debian/vendor-licences.tsv is not what make-orig.sh gives for these modules" >&2; exit 1; }
# The verbatim legal texts are not kept in git (they carry their authors' addresses): they come from the module cache, make-orig.sh read them,
# and each must be the file debian/vendor-licences.tsv pins by sha256, with none extra and none missing.
cp -a "$WORK/orig/vendor-licences" "$WORK/$SRC/debian/vendor-licences"
python3 - "$WORK/$SRC/debian/vendor-licences.tsv" "$WORK/$SRC/debian/vendor-licences" <<'PY'
import csv, hashlib, os, sys
table, root = sys.argv[1:3]
want = {}
for row in csv.reader(open(table, encoding='utf-8'), delimiter='\t'):
	if not row or row[0].startswith('#'):
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
	sys.exit('debian/vendor-licences does not match debian/vendor-licences.tsv:\n  ' + '\n  '.join(problems))
print(f'{len(want)} legal files match the pinned hashes')
PY
DEBV=$(dpkg-parsechangelog -l "$WORK/$SRC/debian/changelog" -S Version)
[ "${DEBV%-*}" = "$UPV" ] || { echo "debian/changelog is $DEBV, not $UPV" >&2; exit 1; }
rm -rf "$WORK/orig"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "$SRC" "$DEBV+lc1" "$REPO"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
