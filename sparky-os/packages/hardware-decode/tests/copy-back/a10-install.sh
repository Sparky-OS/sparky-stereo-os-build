#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: GPL-3.0-or-later
# Installs the ORDER 234 cohort from its kit directory on the machine under
# test (the main session runs it on the A10): the packages it needs, and
# every other package of the kit that is already installed, so nothing new
# arrives besides them. Checks the kit's SHA256SUMS first and prints the
# installed versions and the GPU capabilities afterwards. Needs sudo -n.
# Usage: a10-install.sh KITDIR
set -euo pipefail
kit=$(cd "$1" && pwd)
cd "$kit"
sha256sum -c --quiet SHA256SUMS
needed=' libmedia-gpu-route0 media-gpu-route-tools mpv libmpv2 libplacebo360 '
debs=()
for deb in *.deb; do
    package=$(dpkg-deb -f "$deb" Package)
    if [[ $needed == *" $package "* ]] ||
       dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
        debs+=("$kit/$deb")
    fi
done
printf '%s\n' "${debs[@]}" > "$kit/install-selection.txt"
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${debs[@]}" 2>&1 | tee "$kit/install-234.log"
dpkg-query -W -f='${Package} ${Version}\n' libmedia-gpu-route0 media-gpu-route-tools mpv libmpv2 libplacebo360 \
    libqt6multimedia6 2>/dev/null | tee "$kit/installed-234.txt"
media-gpu-route-query --capabilities | tee "$kit/capabilities-234.txt"
