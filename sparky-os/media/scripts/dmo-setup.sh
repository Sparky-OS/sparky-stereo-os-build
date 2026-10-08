#!/bin/sh
# Inside a debian:testing container (root): dmo's repository (forky = Debian testing) with deb-src,
# its keyring installed from the deb-multimedia-keyring package, then switched to Signed-By.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get -y install --no-install-recommends ca-certificates curl gnupg dpkg-dev >/dev/null
cat >/etc/apt/sources.list.d/dmo-bootstrap.sources <<S
Types: deb
URIs: https://www.deb-multimedia.org
Suites: forky
Components: main non-free
Trusted: yes
S
apt-get update -qq
apt-get -y install --no-install-recommends deb-multimedia-keyring >/dev/null
rm -f /etc/apt/sources.list.d/dmo-bootstrap.sources
sha256sum /usr/share/keyrings/deb-multimedia-keyring.pgp
dpkg -s deb-multimedia-keyring | grep -E '^(Package|Version)'
cat >/etc/apt/sources.list.d/dmo.sources <<S
Types: deb deb-src
URIs: https://www.deb-multimedia.org
Suites: forky
Components: main non-free
Signed-By: /usr/share/keyrings/deb-multimedia-keyring.pgp
S
# Debian's deb-src too (the build-deps and the comparison of sources)
sed -i '0,/^Types: deb$/s//Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources
apt-get update -qq
