#!/bin/bash
# usage: debbuild.sh <srcpkg> <upstream-version> <epoch:version-1> <new-version> <patchdir> <patchname>
set -e
pkg=$1; uv=$2; oldv=$3; newv=$4; pdir=$5; pname=$6
export HOME=/o
rm -rf /o/deb/$pkg; mkdir -p /o/deb/$pkg; cd /o/deb/$pkg
cp /o/src/${pkg}_*.orig.tar.* /o/src/${pkg}_*.debian.tar.xz /o/src/${pkg}_*.dsc . 
dpkg-source -x ${pkg}_*.dsc >/dev/null
cd ${pkg}-*/
mkdir -p debian/patches
cat /o/patches/$pdir/*.patch > debian/patches/$pname
echo $pname >> debian/patches/series
if [ -n "${ADD_DEP:-}" ]; then sed -i "/^Package: ${pkg}\$/,/^\$/ s/^Depends: /Depends: ${ADD_DEP}, /" debian/control; grep -A12 "^Package: ${pkg}\$" debian/control | grep Depends; fi
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Campos Ramos"
dch -v $newv -D unstable --force-distribution "${DCH_MSG:-Add an optional stereo 3D view (--stereo): two cameras around the usual one, one scene, left and right buffers.}"
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc >/o/deb/$pkg.build.log 2>&1; echo build=$?
tail -3 /o/deb/$pkg.build.log
