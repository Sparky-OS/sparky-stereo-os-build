#!/bin/bash
# SPDX-License-Identifier: MIT
# Inside a disposable builder: build a complete retained descriptor, with real receipts.
set -euo pipefail
: "${DSC:?set the retained descriptor}" "${RP_UID:?}" "${RP_GID:?}"
sh /run/https-only-apt.sh
install -m644 /keys/deb-multimedia-keyring.gpg /usr/share/keyrings/deb-multimedia-keyring.pgp
install -m644 /keys/sparky-repo.asc /etc/apt/trusted.gpg.d/sparky-repo.asc
cat > /etc/apt/sources.list.d/qualification.sources <<'EOF'
Types: deb
URIs: https://www.deb-multimedia.org
Suites: forky
Components: main non-free
Signed-By: /usr/share/keyrings/deb-multimedia-keyring.pgp

Types: deb
URIs: https://repo.sparkylinux.org/
Suites: core tiamat
Components: main
Signed-By: /etc/apt/trusted.gpg.d/sparky-repo.asc

Types: deb
URIs: file:/base
Suites: mashtabba
Components: main
Signed-By: /base/sparky-stereo-repo.asc

Types: deb
URIs: file:/pool
Suites: ./
Trusted: yes
EOF
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
export DEBIAN_FRONTEND=noninteractive DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
apt-get -o APT::Update::Error-Mode=any -y update
setpriv --reuid="$RP_UID" --regid="$RP_GID" --clear-groups dpkg-source -x "$DSC" /work/source
apt-get -y --no-install-recommends build-dep /work/source
mkdir -p /work/home
chown "$RP_UID:$RP_GID" /work/home
export HOME=/work/home
setpriv --reuid="$RP_UID" --regid="$RP_GID" --clear-groups bash -euc '
  export DEB_BUILD_OPTIONS=parallel=4
  cd /work/source
  dpkg-buildpackage -us -uc -b -j4
  python3 -m lean.release check-debs /work/*.deb
'
