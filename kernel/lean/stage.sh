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

# Signing must precede the payload manifest. The optional path is supplied only
# by the release coordinator; a source rebuild needs no private signing key.
if [ -n "${SPARKY_SIGNING_KEY_DIR:-}" ]; then
    image=debian/linux-image-${RELEASE}/boot/vmlinuz-${RELEASE}
    sbsign --key "$SPARKY_SIGNING_KEY_DIR/key.pem" \
        --cert "$SPARKY_SIGNING_KEY_DIR/cert.pem" --output "$image.signed" "$image"
    mv "$image.signed" "$image"
    sbverify --cert "$SPARKY_SIGNING_KEY_DIR/cert.pem" "$image"
fi
