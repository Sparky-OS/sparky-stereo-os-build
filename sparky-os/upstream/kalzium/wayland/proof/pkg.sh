#!/bin/bash
# in kdesci-build: pkg.sh <srcpkg> <dsc basename in /src> <newversion> <patchfile in /patches> <patch name>
set -e
pkg=$1; dsc=$2; newv=$3; patch=$4; pname=$5
export HOME=/o/home
D=/o/deb/$pkg-${newv#*:}; rm -rf $D; mkdir -p $D; cd $D; cp /src/${pkg}_* .
dpkg-source -x $dsc >/dev/null
cd ${pkg}-*/
cp /o/patches/$patch debian/patches/$pname; echo $pname >> debian/patches/series
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Campos Ramos"
dch -v $newv -D unstable --force-distribution "${DCH_MSG:-Wayland fixes}"
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc >$D.build.log 2>&1; echo build=$?
tail -3 $D.build.log
