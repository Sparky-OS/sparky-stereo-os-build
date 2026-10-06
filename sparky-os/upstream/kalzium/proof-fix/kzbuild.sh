#!/bin/bash
# usage: kzbuild.sh <outname> <newversion> <changelog msg> <patch>... [env ADD_DEP=...]  (patches in /o/patches, applied in order)
set -e
out=$1; newv=$2; msg=$3; shift 3
export HOME=/o/home
pkg=kalzium
rm -rf /o/deb/$out; mkdir -p /o/deb/$out; cd /o/deb/$out
cp /o/src/${pkg}_*.orig.tar.* /o/src/${pkg}_*.debian.tar.xz /o/src/${pkg}_*.dsc .
dpkg-source -x ${pkg}_*.dsc >/dev/null
cd ${pkg}-*/
for p in "$@"; do n=$(basename $p); cp /o/patches/$p debian/patches/$n; echo $n >> debian/patches/series; done
if [ -n "${ADD_DEP:-}" ]; then sed -i "/^Package: ${pkg}\$/,/^\$/ s/^Depends: /Depends: ${ADD_DEP}, /" debian/control; fi
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Campos Ramos"
dch -v $newv -D unstable --force-distribution "$msg"
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc >/o/deb/$out.build.log 2>&1; echo build=$?
tail -3 /o/deb/$out.build.log
