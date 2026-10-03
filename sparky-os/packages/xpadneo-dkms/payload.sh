#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
V=0.10.0+git3879ba0
S=$D/usr/src/hid-xpadneo-$V
mkdir -p "$S" "$D/usr/lib/udev/rules.d" "$D/usr/lib/modprobe.d"
cp -r "$HERE/upstream/src" "$S/"
find "$S" -name AGENTS.md -delete
sed -e "s/@DO_NOT_CHANGE@/$V/" -e '/^POST_INSTALL=/d' -e '/^POST_REMOVE=/d' "$HERE/upstream/dkms.conf.in" >"$S/dkms.conf"
install -m644 "$HERE"/upstream/etc-udev-rules.d/* "$D/usr/lib/udev/rules.d/"
install -m644 "$HERE/upstream/etc-modprobe.d/xpadneo.conf" "$D/usr/lib/modprobe.d/xpadneo.conf"
install -m644 "$HERE"/upstream/LICENSES/* "$D/usr/share/doc/xpadneo-dkms/"
install -m644 "$HERE/upstream/LICENSE.md" "$D/usr/share/doc/xpadneo-dkms/LICENSE.upstream.md"
install -m755 "$HERE/postinst" "$D/DEBIAN/postinst"
install -m755 "$HERE/prerm" "$D/DEBIAN/prerm"
