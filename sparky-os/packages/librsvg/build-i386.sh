#!/bin/bash
# Sparky Stereo OS: builds librsvg 2.63.3+dfsg-1+stereo3d1+lc1 for i386 from the amd64 build's +lc1 source package.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# librsvg2-2 and librsvg2-common are Multi-Arch: same, and the edition's libavcodec63:i386 (Steam, Wine) needs
# librsvg2-2:i386, so an amd64 build alone is kept back on those systems. Every architecture comes from the one source
# package (dpkg-buildpackage -B on the same .dsc, so the changelog and /usr/share files are the same bytes).
# A guard stops the build below 12 GB free on / or 10 GB on the WORK disk.
# Usage: build-i386.sh WORK AMD64_LC_DIR PREVIOUS_DIR   (AMD64_LC_DIR: build.sh's WORK/lc, holding the +lc1 .dsc and its
#   files; PREVIOUS_DIR: the i386 predecessor .debs for the link gate, Debian's 2.63.3+dfsg-1 i386 build)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../config/local-config.sh"
sparky_need SPARKY_REPO_DIR
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate, mounted at /archive; see sparky-os/lean/archive.md}"
WORK=$(mkdir -p "$1" && cd "$1" && pwd)
SRC=$(cd "$2" && pwd)
PREV=$(cd "$3" && pwd)
[ -z "$(ls -A "$WORK")" ] || { echo "$WORK is not empty" >&2; exit 1; }
name=librsvg-build-i386-$$
docker run -d --name "$name" --cpus 4 --platform linux/386 \
	--security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
	-e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$SPARKY_LC_ARCHIVE_DIR":/archive:ro \
	-v "$WORK":/work -v "$SRC":/src:ro -v "$SPARKY_REPO_DIR":/repo:ro -v "$PREV":/prev:ro -v "$HERE/../..":/toolkit:ro \
	-v /usr/share/keyrings/deb-multimedia-keyring.pgp:/usr/share/keyrings/deb-multimedia-keyring.pgp:ro \
	sparky-lc-migration:20261020-i386 bash -c '
trap "chown -R 1000:1000 /work" EXIT
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS="parallel=4 nocheck"
export DEBFULLNAME="Daniel Ramos (Capitain Jack)" DEBEMAIL=Capitain_Jack@yahoo.com
printf "deb [trusted=yes] file:/repo mashtabba main\n" > /etc/apt/sources.list.d/edition.list
printf "deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n" > /etc/apt/sources.list.d/multimedia.list
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" > /etc/apt/preferences.d/edition
cd /work
dpkg-source -x /src/librsvg_2.63.3+dfsg-1+stereo3d1+lc1.dsc source > /work/source-extract.log
apt-get -y update > /work/build-dep.log 2>&1
apt-get -y --no-install-recommends build-dep /work/source >> /work/build-dep.log 2>&1
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
dpkg-query -W -f "\${Package} \${Version} \${Architecture}\n" rustc cargo libcairo2-dev libdav1d-dev > /work/build-toolchain.txt
mkdir -p "$SPARKY_LC_SCRATCH"
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -B -j4
cd /work
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*+lc1_i386.deb
rm -rf /work/source' > /dev/null
guard=ok
while [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ]; do
	root=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
	disk=$(df -BG --output=avail "$WORK" | tail -1 | tr -dc 0-9)
	if [ "$root" -lt 12 ] || [ "$disk" -lt 10 ]; then
		echo "stopping the build: / has ${root} GB and $WORK ${disk} GB free" >&2
		docker kill "$name" >/dev/null
		guard=stopped
	fi
	sleep 5
done
docker logs "$name" > "$WORK/build.log" 2>&1
status=$(docker inspect -f '{{.State.ExitCode}}' "$name")
docker rm "$name" >/dev/null
[ "$guard" = ok ] && [ "$status" = 0 ] || { echo "the build failed (exit $status, guard $guard): $WORK/build.log" >&2; exit 1; }
# the files every architecture shares are the same bytes (Multi-Arch: same); the Lean Code record is named after its
# architecture (/usr/share/dpkg-stereo/lc/PACKAGE/ARCH.json), so the twins carry one each
python3 - "$SRC" "$WORK" <<'SAME'
import subprocess, sys, tempfile
from pathlib import Path
src, work = Path(sys.argv[1]), Path(sys.argv[2])
checked = 0
for deb in sorted(work.glob('*_i386.deb')):
    if '-dbgsym_' in deb.name:
        continue
    twin = src / deb.name.replace('_i386.deb', '_amd64.deb')
    if not twin.exists():
        continue
    trees = {}
    for arch, path in (('amd64', twin), ('i386', deb)):
        root = Path(tempfile.mkdtemp(dir=work))
        subprocess.run(['dpkg-deb', '-x', str(path), str(root)], check=True)
        share = root / 'usr/share'
        files = {}
        for f in share.rglob('*') if share.exists() else ():
            if f.is_file() and not f.is_symlink():
                rel = f.relative_to(share).as_posix()
                if rel.startswith('dpkg-stereo/lc/') and rel.endswith('/' + arch + '.json'):
                    continue
                files[rel] = f.read_bytes()
        trees[arch] = files
        subprocess.run(['rm', '-rf', str(root)], check=True)
    if trees['amd64'] != trees['i386']:
        diff = sorted(set(trees['amd64']) ^ set(trees['i386'])) or [k for k in trees['amd64'] if trees['amd64'][k] != trees['i386'].get(k)]
        sys.exit('%s: /usr/share differs between amd64 and i386: %s' % (deb.name, diff[:5]))
    checked += 1
print('i386: %d packages with an amd64 twin, /usr/share identical apart from each Lean Code record' % checked)
SAME
