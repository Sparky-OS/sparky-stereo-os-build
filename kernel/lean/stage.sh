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
sh debian/kernel-recipe/headers-postinst.sh "$RELEASE" > "$headers/DEBIAN/postinst"
chmod 0755 "$headers/DEBIAN/postinst"

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
