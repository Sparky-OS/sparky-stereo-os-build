#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
source debian/kernel-build.env
for kind in image headers; do
    name=linux-${kind}-${RELEASE}
    dpkg-deb -R "${name}_${PACKAGE_VERSION}_amd64.deb" "debian/$name"
done
headers=debian/linux-headers-${RELEASE}
destination=$headers/usr/src/linux-headers-${RELEASE}
cp build/.config "$destination/.config"
objcopy -j .BTF -j .BTF_ids build/vmlinux "$destination/vmlinux"
chmod 0644 "$destination/.config" "$destination/vmlinux"
readelf -SW "$destination/vmlinux" > build/header-sections.txt
grep -q ' \.BTF ' build/header-sections.txt
test -s "$destination/Module.symvers"

# What Debian's kbuild package ships and the upstream external-module install leaves out (ORDER 222):
# the configuration tool (make oldconfig, menuconfig on the installed headers), the certificate extractor
# and the x86 relocation tool, built by this very build. genksyms is not needed: CONFIG_MODVERSIONS is off.
for tool in scripts/kconfig/conf certs/extract-cert arch/x86/tools/relocs; do
    test -x "build/$tool"
    install -D -m 0755 "build/$tool" "$destination/$tool"
done
# /lib/modules/RELEASE/source, next to build: Debian's headers link it to the shared header package; ours is
# one package, so both links name the same directory.
ln -s "/usr/src/linux-headers-${RELEASE}" "$headers/lib/modules/${RELEASE}/source"
test "$(readlink "$headers/lib/modules/${RELEASE}/build")" = "/usr/src/linux-headers-${RELEASE}"

# The compiler the kernel was built with, read from the configuration that built it: Debian's headers
# depend on gcc-16-for-host (the exact major version), so DKMS never meets a compiler the kernel was not
# built with after the default gcc moves on. Plain gcc stays the alternative where the versioned package
# is not available.
compiler=$(sed -n 's/^CONFIG_CC_VERSION_TEXT="\(.*\)"$/\1/p' build/.config)
if [[ "$compiler" =~ ^gcc\ \(.*\)\ ([0-9]+)\.[0-9]+\.[0-9]+$ ]]; then
    echo "kernel:Compiler=gcc-${BASH_REMATCH[1]}-for-host | gcc" > "debian/linux-headers-${RELEASE}.substvars"
else
    echo "Unsupported CONFIG_CC_VERSION_TEXT: $compiler" >&2
    exit 1
fi
echo "$compiler" > build/compiler.txt

# Maintainer scripts. The image package gets Debian's (kernel/lean/maint, release in place of @RELEASE@): the
# upstream builddeb scripts only run run-parts. The headers postinst is Debian's too (headers-postinst.sh).
for script in preinst postinst prerm postrm; do
    sed "s/@RELEASE@/${RELEASE}/" "debian/kernel-recipe/maint/image.$script" > "debian/linux-image-${RELEASE}/DEBIAN/$script"
    chmod 0755 "debian/linux-image-${RELEASE}/DEBIAN/$script"
done
sh debian/kernel-recipe/headers-postinst.sh "$RELEASE" > "$headers/DEBIAN/postinst"
chmod 0755 "$headers/DEBIAN/postinst"

# linux-libc-dev, base flavour only (build.sh made it): the userspace API headers of this very tree.
if [ -d build/libc-dev ]; then
    mkdir -p debian/linux-libc-dev
    cp -a build/libc-dev/. debian/linux-libc-dev/
fi

# dh_installdeb merges helper fragments with debian/package.script templates.
# Scripts only in the extracted DEBIAN/ directory are overwritten when a helper
# (notably dh_installmodules) supplies its own postinst/postrm fragments.
for kind in image headers; do
    name=linux-${kind}-${RELEASE}
    for script in preinst postinst prerm postrm; do
        original=debian/$name/DEBIAN/$script
        [ -f "$original" ] || continue
        test "$(grep -c '^set -e$' "$original")" = 1
        if grep -q '^#DEBHELPER#$' "$original"; then
            cp "$original" "debian/$name.$script"
        else
            sed '/^set -e$/a #DEBHELPER#' "$original" > "debian/$name.$script"
        fi
        chmod 0755 "debian/$name.$script"
    done
done

# Signing must precede the payload manifest. The optional path is supplied only
# by the release coordinator; a source rebuild needs no private signing key.
if [ -n "${SPARKY_SIGNING_KEY_DIR:-}" ]; then
    image=debian/linux-image-${RELEASE}/boot/vmlinuz-${RELEASE}
    sbsign --key "$SPARKY_SIGNING_KEY_DIR/key.pem" \
        --cert "$SPARKY_SIGNING_KEY_DIR/cert.pem" --output "$image.signed" "$image"
    mv "$image.signed" "$image"
    sbverify --cert "$SPARKY_SIGNING_KEY_DIR/cert.pem" "$image"
fi
