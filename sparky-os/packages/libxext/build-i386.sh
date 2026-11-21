#!/bin/bash
# Sparky Stereo OS: builds libxext 2:1.3.4-1+stereo3d1+lc1 for i386 from the amd64 build's +lc1 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# libxext6 and libxext-dev are Multi-Arch: same, and 32-bit programs (Steam, Wine) load libXext, so an amd64 build alone is
# kept back on those systems. Every architecture comes from the one source package (dpkg-buildpackage -B on the same .dsc, so
# the changelog and /usr/share files are the same bytes).
# Usage: build-i386.sh WORK AMD64_LC_DIR PREVIOUS_DIR   (AMD64_LC_DIR: build.sh's WORK/lc, holding the +lc1 .dsc and its
#   files; PREVIOUS_DIR: the i386 predecessor .debs for the link gate, Debian's libxext6 and libxext-dev 2:1.3.4-1+b4 i386)
# SPARKY_BUILD_IMAGE names the builder image when it is not sparky-lc-migration:20261020-i386.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate, mounted at /archive; see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
PREV=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
IMAGE=${SPARKY_BUILD_IMAGE:-sparky-lc-migration:20261020-i386}
name=${SPARKY_BUILD_CONTAINER:-libxext-build-i386-$$}
sparky_provenance_init "$IMAGE"
docker run -d --name "$name" --pull=never --ulimit core=1 --cpus 4 --platform linux/386 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	"${SPARKY_PROV_ARGS[@]}" -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"$IMAGE" bash -c '
trap "chown -R 1000:1000 /work" EXIT
set -euo pipefail
sh /run/https-only-apt.sh
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="parallel=4 nocheck" DEB_BUILD_PROFILES=noudeb
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
printf "deb [trusted=yes] file:/repo mashtabba main\n" > /etc/apt/sources.list.d/edition.list
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/edition
for v in 2:1.3.4-1+b4 2:1.3.4-1; do
	dpkg --compare-versions 2:1.3.4-1+stereo3d1+lc1 gt "$v"
	echo "$(dpkg --print-architecture): 2:1.3.4-1+stereo3d1+lc1 > $v"
done
cd /work
dpkg-source -x /src/libxext_1.3.4-1+stereo3d1+lc1.dsc source > /work/source-extract.log
apt-get -y update > /work/build-dep.log 2>&1
apt-get -y --no-install-recommends build-dep /work/source >> /work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
dpkg-query -W -f "\${Package} \${Version} \${Architecture}\n" gcc debhelper libx11-dev x11proto-dev pkgconf xutils-dev > /work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -B -j4
cd /work
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_i386.deb
rm -rf /work/source' > /dev/null
status=$(docker wait "$name")
docker logs "$name" > "$WORK/build.log" 2>&1
docker rm "$name" >/dev/null
[ "$status" = 0 ] || { echo "the build failed (exit $status): $WORK/build.log" >&2; exit 1; }
# in every Multi-Arch: same package (the ones amd64 and i386 install side by side) each path both architectures ship is the
# same bytes, as dpkg requires; a path only one of them ships (/usr/lib/TRIPLET/..., the Lean Code record
# /usr/share/dpkg-stereo/lc/PACKAGE/ARCH.json, an -lc-hr companion's /usr/share/dpkg-stereo/hr/PACKAGE/ARCH/) never collides
python3 - "$SRC" "$WORK" <<'SAME'
import subprocess, sys, tempfile
from pathlib import Path
src, work = Path(sys.argv[1]), Path(sys.argv[2])
checked = shared = 0
for deb in sorted(work.glob('*_i386.deb')):
    if '-dbgsym_' in deb.name:
        continue
    twin = src / deb.name.replace('_i386.deb', '_amd64.deb')
    if not twin.exists():
        continue
    if subprocess.run(['dpkg-deb', '-f', str(deb), 'Multi-Arch'], capture_output=True, text=True, check=True).stdout.strip() != 'same':
        continue
    trees = {}
    for arch, path in (('amd64', twin), ('i386', deb)):
        root = Path(tempfile.mkdtemp(dir=work))
        subprocess.run(['dpkg-deb', '-x', str(path), str(root)], check=True)
        trees[arch] = {f.relative_to(root).as_posix(): f.read_bytes()
                       for f in root.rglob('*') if f.is_file() and not f.is_symlink()}
        subprocess.run(['rm', '-rf', str(root)], check=True)
    common = set(trees['amd64']) & set(trees['i386'])
    differ = sorted(rel for rel in common if trees['amd64'][rel] != trees['i386'][rel])
    if differ:
        sys.exit('%s: files both architectures ship differ: %s' % (deb.name, differ[:5]))
    checked += 1
    shared += len(common)
if not checked:
    sys.exit('no Multi-Arch: same package with an amd64 twin was checked')
print('i386: %d Multi-Arch: same packages with an amd64 twin, the %d files they both ship the same bytes' % (checked, shared))
SAME
