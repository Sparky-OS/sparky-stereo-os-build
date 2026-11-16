#!/bin/bash
set -euo pipefail
ulimit -c 0
trap 'chown -R "$OWNER" /work' EXIT
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/
printf 'deb [signed-by=/usr/share/keyrings/sparky-stereo-repo.asc] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
apt-get -y update
apt-get -y --no-install-recommends install build-essential debhelper devscripts dpkg-dev python3 deb-multimedia-keyring bubblewrap frei0r-plugins
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
apt-get -y update
cd /work
dpkg-source -x /src/*+stereo3d15+lc1.dsc tree
apt-get -y --no-install-recommends build-dep ./tree
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
mkdir -p /work/link-scratch
chown -R builder:builder /work
cd tree
runuser -u builder -- dpkg-buildpackage "$FLAGS" -us -uc -j4
runuser -u builder -- bash /work/fate.sh /work/tree /work/fate
cd /work
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/*.deb
sha256sum ./*.deb ./*.changes ./*.buildinfo > SHA256SUMS
