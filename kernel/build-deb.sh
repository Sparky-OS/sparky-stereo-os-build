#!/bin/sh
# Builds the package's kernel (the linux submodule, branch stereo3d) as Debian
# packages, with the running Debian kernel's whole configuration so every
# driver and feature Debian enables is kept; only the settings a rebuild
# outside Debian cannot honour change (Debian's signing keys) and what the edition
# adds (kernel/configure.sh: BTF and sched_ext, four Realtek drivers).
#
#   kernel/build-deb.sh [out-dir]     (default /K3D/temp/linux-stereo3d-out)
#
# Runs in a debian:testing container (the host is not touched); the tree is
# mounted read-write, the packages land in out-dir. Install with dpkg -i;
# booting it is the owner's step (keep the distribution kernel as default).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$HERE/linux}
OUT=${1:-/K3D/temp/linux-stereo3d-out}
CONFIG=${CONFIG:-/boot/config-$(uname -r)}
JOBS=${JOBS:-$(nproc)}
PKGVER=${PKGVER:-1}
mkdir -p "$OUT"
cp "$CONFIG" "$OUT/base.config"
docker run --rm -v "$SRC":/src -v "$OUT":/out -v "$HERE/kernel":/kernel:ro -e JOBS="$JOBS" -e PKGVER="$PKGVER" debian:testing sh -euc '
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential bc bison flex libssl-dev libelf-dev dwarves cpio kmod rsync python3 git ca-certificates debhelper libdw-dev zstd >/dev/null
cd /src
git config --global --add safe.directory /src
git log --oneline -1
sh /kernel/configure.sh /out/base.config
grep -E "^CONFIG_DRM_(AMDGPU|NOUVEAU)=" .config
make -s -j"$JOBS" bindeb-pkg LOCALVERSION=-stereo3d KDEB_PKGVERSION="$PKGVER"
cp ../linux-image-*-stereo3d_"$PKGVER"_amd64.deb ../linux-headers-*-stereo3d_"$PKGVER"_amd64.deb /out/
sha256sum /out/*.deb
'
