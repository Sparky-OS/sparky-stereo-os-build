#!/bin/bash
# Sparky Stereo OS: Vibe 3.2.2 from upstream's signed release, in a throwaway sparky-pkg-base:amd64 container.
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/05
# Copyright 2026 under the GNU GPL3 License
# Upstream releases the .deb it builds (Tauri, Rust, WebKitGTK; the engine vibe-server is a Rust binary with
# ggml and Vulkan). We verify the release's minisign signature against the public key in the tagged
# source (desktop/src-tauri/tauri.conf.json, plugins.updater.pubkey), and the source package carries both
# the tagged source (main orig tarball) and the verified release .deb (component "release"), so what we
# ship can be unpacked and compared with `dpkg-source -x`.
# Usage: build.sh [workdir]   (default ${SPARKY_WORKSPACES}/hand-installed-apps/vibe/build)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
WORK=${1:-${SPARKY_WORKSPACES:?}/hand-installed-apps/vibe/build}
VER=3.2.2
mkdir -p "$WORK"
docker run --rm --platform linux/amd64 -e HOST_UID=$(id -u) -e VER=$VER -v "$WORK":/out -v "$HERE/debian":/debian-ours:ro -v "$HERE/../..":/toolkit:ro sparky-pkg-base:amd64 bash -c '
set -euo pipefail
sed -i "s/^Suites: unstable/Suites: testing testing-updates/" /etc/apt/sources.list.d/debian.sources
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
apt-get update -qq >/dev/null; apt-get install -y -qq ca-certificates curl git dpkg-dev devscripts build-essential fakeroot lintian xz-utils minisign node-acorn nodejs perl python3-yaml libayatana-appindicator3-1 libgtk-3-0t64 libwebkit2gtk-4.1-0 libxdo3 >/dev/null
cd /out && rm -rf work && mkdir work && cd work
git clone -q --depth 1 --branch v$VER https://github.com/thewh1teagle/vibe.git up
echo "tag commit: $(git -C up rev-parse HEAD)"
base=https://github.com/thewh1teagle/vibe/releases/download/v$VER
curl -fsSL -o vibe_${VER}_amd64.deb $base/vibe_${VER}_amd64.deb
curl -fsSL -o vibe_${VER}_amd64.deb.sig $base/vibe_${VER}_amd64.deb.sig
python3 - <<PY
import json,base64
d=json.load(open("up/desktop/src-tauri/tauri.conf.json"))
open("vibe.pub","wb").write(base64.b64decode(d["plugins"]["updater"]["pubkey"]))
open("vibe.sig","wb").write(base64.b64decode(open("vibe_${VER}_amd64.deb.sig").read()))
PY
cat vibe.pub
echo "== minisign verify"; minisign -V -p vibe.pub -x vibe.sig -m vibe_${VER}_amd64.deb
sha256sum vibe_${VER}_amd64.deb
mkdir vibe-$VER
git -C up archive --format=tar HEAD | tar xf - -C vibe-$VER
tar --sort=name --mtime=@1789000000 --owner=0 --group=0 -cJf vibe_$VER.orig.tar.xz vibe-$VER
mkdir release && cp vibe_${VER}_amd64.deb vibe_${VER}_amd64.deb.sig vibe.pub vibe.sig release/
tar --sort=name --mtime=@1789000000 --owner=0 --group=0 -cJf vibe_$VER.orig-release.tar.xz release
mkdir -p vibe-$VER/release && cp release/* vibe-$VER/release/
cp -a /debian-ours vibe-$VER/debian
python3 /toolkit/packages/vibe/prepare-lean.py vibe-$VER "$VER-1+lc1"
cd vibe-$VER
if ! dpkg-buildpackage -us -uc -sa > ../build.log 2>&1; then
    tail -60 ../build.log
    exit 1
fi
tail -15 ../build.log
cd ..
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
lintian -I --pedantic vibe_*.deb vibe_*.dsc > lintian.txt 2>&1 || true
head -60 lintian.txt
chown -R $HOST_UID:$HOST_UID /out; ls /out/work
'
