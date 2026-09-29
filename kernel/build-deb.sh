#!/bin/sh
# Builds the package's kernel (the linux submodule, branch stereo3d) as Debian
# packages, with the running Debian kernel's whole configuration so every
# driver and feature Debian enables is kept; only the settings a rebuild
# outside Debian cannot honour change (Debian's signing keys, debug info).
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
mkdir -p "$OUT"
cp "$CONFIG" "$OUT/base.config"
docker run --rm -v "$SRC":/src -v "$OUT":/out -e JOBS="$JOBS" debian:testing sh -euc '
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential bc bison flex libssl-dev libelf-dev dwarves cpio kmod rsync python3 git ca-certificates debhelper libdw-dev zstd >/dev/null
cd /src
git config --global --add safe.directory /src
git log --oneline -1
cp /out/base.config .config
scripts/config --set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" \
  --disable DEBUG_INFO --disable DEBUG_INFO_DWARF5 --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
  --enable DEBUG_INFO_NONE --disable MODULE_SIG_ALL --module DRM_NOUVEAU --module DRM_AMDGPU
make -s olddefconfig
grep -E "^CONFIG_DRM_(AMDGPU|NOUVEAU)=" .config
make -s -j"$JOBS" bindeb-pkg LOCALVERSION=-stereo3d KDEB_PKGVERSION=1
cp ../linux-image-*-stereo3d_1_amd64.deb ../linux-headers-*-stereo3d_1_amd64.deb /out/
sha256sum /out/*.deb
'
