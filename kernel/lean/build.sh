#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runs from a retained, patched kernel source package. Kbuild's generated Debian
# directory stays in build/, separate from the edition's source recipe.
set -euo pipefail
umask 022
source debian/kernel-build.env
root=$PWD
obj=$root/build
export KBUILD_BUILD_USER=sparky KBUILD_BUILD_HOST=stereo
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP=$(date -u -d "@$UPSTREAM_TIMESTAMP" '+%a %b %e %H:%M:%S UTC %Y')
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
export KBUILD_VERBOSE=0 DEB_BUILD_OPTIONS=parallel=4

erase_module_key() {
    for key in signing_key.pem signing_key.x509 x509.genkey; do
        if [ -f "$obj/certs/$key" ]; then shred -u "$obj/certs/$key"; fi
    done
}
trap erase_module_key EXIT

mkdir -p "$obj"
if [ "$SMOKE" = 1 ]; then
    make O="$obj" tinyconfig
    KCONFIG_CONFIG="$obj/.config" scripts/kconfig/merge_config.sh -m -O "$obj" \
        "$obj/.config" debian/kernel-recipe/tests/smoke.fragment
    make O="$obj" olddefconfig
else
    bash debian/kernel-recipe/configure.sh "$FLAVOUR" "$obj"
    make O="$obj" rustavailable
fi
for option in MODULE_SIG_ALL DEBUG_INFO_BTF BLK_DEV_LOOP; do
    grep -Eq "^CONFIG_$option=[ym]$" "$obj/.config"
done
if [ "$SMOKE" != 1 ]; then
    for option in RUST SCHED_CLASS_EXT SCHED_BORE; do
        grep -qx "CONFIG_$option=y" "$obj/.config"
    done
    grep -qx CONFIG_ANDROID_BINDER_IPC=m "$obj/.config"
    if [ "$FLAVOUR" = rt ]; then grep -qx CONFIG_PREEMPT_RT=y "$obj/.config"; fi
    if [ "$FLAVOUR" = v3 ]; then grep -qx CONFIG_X86_64_VERSION=3 "$obj/.config"; fi
fi

make -j4 O="$obj" bindeb-pkg LOCALVERSION="$LOCALVERSION" \
    KDEB_PKGVERSION="$PACKAGE_VERSION" KDEB_CHANGELOG_DIST=unstable \
    DPKG_FLAGS='-Ppkg.linux-upstream.nokerneldbg'
test "$(cat "$obj/include/config/kernel.release")" = "$RELEASE"
cp "$obj/.config" debian/built.config

# The userspace API headers of this tree, as linux-libc-dev (ORDER 222), and Debian's linux-libc-dev-ARCH-cross
# packages from the same files (ORDER 256). Built from the base flavour only: the UAPI is the same in every
# flavour and the package names are one. The kernel's own headers_install runs for every architecture Debian's
# package covers, in separate output directories (the tree itself stays clean).
if [ "$FLAVOUR" = base ]; then
    python3 debian/kernel-recipe/libc-dev.py "$root" "$obj/libc-dev-work" "$obj/libc-dev" "$obj/libc-dev-cross"
    rm -rf "$obj/libc-dev-work"
fi

# Test the nested archives before the final staging and Lean Code pass.
image="linux-image-${RELEASE}_${PACKAGE_VERSION}_amd64.deb"
headers="linux-headers-${RELEASE}_${PACKAGE_VERSION}_amd64.deb"
test -s "$image" && test -s "$headers"
dpkg-deb --fsys-tarfile "$image" > build/image-files.tar
python3 debian/check-module-signature.py build/image-files.tar
for archive in "$image" "$headers"; do
    dpkg-deb --fsys-tarfile "$archive" | tar -tf - > build/archive-files.txt
    if grep -q signing_key build/archive-files.txt; then
        echo "Kernel package unexpectedly carries a build signing key" >&2
        exit 1
    fi
done
rm build/image-files.tar build/archive-files.txt
