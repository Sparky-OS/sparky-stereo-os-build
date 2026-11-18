#!/bin/bash
# container: a flat repository of the three built packages with the edition's origin, the install-time download hook of sparky-stereo-apt, then the install of sparky-pjeoffice from apt
set -e
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
sh /run/https-only-apt.sh
mkdir -p /srv/repo && cp /debs/*.deb /srv/repo/ && cd /srv/repo
apt-get -y -q install --no-install-recommends apt-utils >/dev/null 2>&1 || true
dpkg-scanpackages . > Packages 2>/dev/null; gzip -k -f Packages
apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo OS" -o APT::FTPArchive::Release::Label="pj18 test" -o APT::FTPArchive::Release::Suite=testing release . > Release
echo "deb [trusted=yes] file:/srv/repo ./" > /etc/apt/sources.list.d/pj18-flat.list
# the shared reader and the apt hook that announce install-time downloads
cd /tmp && apt-get download sparky-stereo-apt >/dev/null 2>&1
dpkg-deb -x sparky-stereo-apt_*.deb /tmp/ssa
cp -a /tmp/ssa/etc/apt/apt.conf.d/61sparky-install-downloads /etc/apt/apt.conf.d/
cp -a /tmp/ssa/usr/lib/sparky-stereo-apt /usr/lib/
mkdir -p /usr/share/sparky && cp -a /tmp/ssa/usr/share/sparky/sparky-stereo-apt /usr/share/sparky/
apt-get update -q 2>&1 | tail -3
echo "== candidates"; apt-cache policy sparky-pjeoffice sparky-pjeoffice-codec | grep -E "^[a-z]|Candidate"
echo "== apt-cache show (the declaration)"; apt-cache show sparky-pjeoffice | grep -E "^(Package|Version|Sparky-Install|Depends|Recommends)" | cut -c1-300
echo "== simulation"; apt-get -s install sparky-pjeoffice | grep -E "^(Inst|The following|[0-9]+ upgraded)" | cut -c1-160
