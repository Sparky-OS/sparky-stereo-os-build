#!/bin/bash
# SPDX-License-Identifier: MIT
# Inside a disposable HTTPS-only builder, with read-only public archive inputs.
set -euo pipefail
sh /run/https-only-apt.sh
install -m644 /keys/deb-multimedia-keyring.gpg /usr/share/keyrings/deb-multimedia-keyring.pgp
install -m644 /keys/sparky-repo.asc /etc/apt/trusted.gpg.d/sparky-repo.asc
cat > /etc/apt/sources.list.d/701-extra.sources <<'EOF'
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
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
setpriv --reuid="$RP_UID" --regid="$RP_GID" --clear-groups bash -euc '
  export OUT=/output BUILD_ROOT=/scratch VERSION=20261118.701 REPO=/catalog
  bash /build/sparky-os/packages/sparky-stereo-meta/build.sh
  python3 /build/tools/publication-reconcile/rebuild-native.py /output/sparky-stereo-meta_20261118.701.dsc /scratch
  python3 -m lean.release check-debs /output/*.deb
'
