#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(realpath "$here/../..")
published=${CALAMARES_SOURCE:?directory containing the published Calamares source closure}
out=$(realpath "${OUT:?empty output directory}")
base=3.4.3~sparky9~4-1+stereo3d3+lc1
version=3.4.3~sparky9~4-1+stereo3d4+lc1
dsc="$published/calamares_$base.dsc"
test -z "$(ls -A "$out")"
printf '%s  %s\n' 0a823de2ebfe2d8c1c77bb9d34365548c91c53013bbdab51d31b94a6bc429bb4 "$dsc" | sha256sum -c
cd "$out"
dpkg-source -x "$dsc" source
cd source
install -m644 "$here/patches/automatic-swap.patch" debian/patches/
echo automatic-swap.patch >> debian/patches/series
mv debian/changelog debian/changelog.previous
cat > debian/changelog <<EOF
calamares ($version) unstable; urgency=medium

  * Describe and create the edition's automatic hibernation and Cushion Swap
    layout, with the selected swap size and the Debian initramfs resume target.

 -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ${SOURCE_DATE_RFC2822:?source date from the recipe}

EOF
cat debian/changelog.previous >> debian/changelog
rm debian/changelog.previous
dpkg-source --before-build .
export DEB_BUILD_OPTIONS="parallel=${BUILD_JOBS:-4}"
dpkg-buildpackage -us -uc -sa "-j${BUILD_JOBS:-4}"
cd "$out"
PYTHONPATH="$toolkit" python3 -m lean.release check-debs ./*.deb
