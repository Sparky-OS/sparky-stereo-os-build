#!/bin/bash
# the rig (ORDER 458): a forky container with the published tree r1107a (file:/repo), deb-multimedia over https, and the published
# sparky-stereo-apt 20261106.1 installed (the pins of today). Sourced by inside.sh.
export DEBIAN_FRONTEND=noninteractive LC_ALL=C
REPO=/repo
OLDDEB=$(ls $REPO/pool/main/s/sparky-stereo-apt/sparky-stereo-apt_20261106.1~sparky9~0+lc1_all.deb)
sh /run/https-only-apt.sh >/dev/null || exit 2
# keep the downloaded .debs in the mounted cache: the next container of the rig reuses them
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get -qq update >/dev/null 2>&1 || exit 2
apt-get install -y -qq $REPO/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2024.9.1+lc1_all.deb $REPO/pool/main/s/sparky-stereo-keyring/sparky-stereo-keyring_20261016~sparky9~0+lc1_all.deb >/tmp/keyrings.log 2>&1 || { tail /tmp/keyrings.log; exit 2; }
cat >/etc/apt/sources.list.d/rig-sparky.sources <<EOS
Types: deb
URIs: file:$REPO
Suites: mashtabba
Components: main
Signed-By: $REPO/sparky-stereo-repo.asc
EOS
cat >/etc/apt/sources.list.d/rig-dmo.sources <<EOS
Types: deb
URIs: https://www.deb-multimedia.org
Suites: forky
Components: main non-free
Signed-By: /usr/share/keyrings/deb-multimedia-keyring.pgp
EOS
mkdir -p /tmp/standin/DEBIAN
printf 'Package: sparky-apt-standin\nVersion: 1\nArchitecture: all\nMaintainer: test <test@example.org>\nProvides: sparky-apt\nDescription: stand-in for sparky-apt (SparkyLinux repository is not in the rig)\n' >/tmp/standin/DEBIAN/control
dpkg-deb --root-owner-group -b /tmp/standin /tmp/sparky-apt-standin_1_all.deb >/dev/null
apt-get -qq update >/dev/null 2>&1 || { echo "apt-get update failed"; exit 2; }
apt-get install -y -qq /tmp/sparky-apt-standin_1_all.deb "$OLDDEB" >/tmp/old-install.log 2>&1 || { tail -20 /tmp/old-install.log; exit 2; }
# the package's own sources point at the real servers: the rig uses its two files instead (the conffiles stay as they are, so no upgrade restores them)
rm -f /etc/apt/sources.list.d/sparky-stereo.sources /etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources
apt-get -qq update >/dev/null 2>&1 || { echo "apt-get update failed"; exit 2; }
