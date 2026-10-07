#!/bin/bash
# in the build image as root. /w = plasmatube work dir. $1 = variant dir name with debian/ (debian-A, debian-B), $2 = out dir
set -e
export DEBIAN_FRONTEND=noninteractive
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/zrepo.list; cp /w/run/pin /etc/apt/preferences.d/sparky-stereo
apt-get -y -qq update >/dev/null 2>&1
rm -rf /b; mkdir /b; cd /b
cp /w/src/plasmatube-26.08.1.tar.xz plasmatube_26.08.1.orig.tar.xz
tar xf plasmatube_26.08.1.orig.tar.xz
cd plasmatube-26.08.1
cp -r /w/$1 debian
if [ -d /w/$1-patches ]; then mkdir -p debian/patches; cp /w/$1-patches/*.patch debian/patches/; (cd debian/patches && ls *.patch | sort > series); fi
apt-get -y -qq --allow-downgrades build-dep . >/w/$2.builddep.log 2>&1 || { tail -20 /w/$2.builddep.log; exit 1; }
dpkg-buildpackage -us -uc >/w/$2.build.log 2>&1; echo build=$?
cd /b; mkdir -p /w/$2; cp *.deb *.dsc *.changes *.orig.tar.xz *.debian.tar.xz /w/$2/ 2>/dev/null; ls /w/$2
lintian -I --pedantic /b/*.changes > /w/$2.lintian.txt 2>&1 || true
chown -R 1000:1000 /w/$2 /w/$2.*
