#!/bin/bash
# in kdesci-build: pkg.sh <srcpkg> <dsc basename in /src> <newversion> <patchfile in /patches> <patch name>
set -e
REPRO=/run/reproducible.py
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: export SOURCE_DATE_EPOCH (python3 sparky-os/repo/reproducible.py epoch RECIPE_DIR) or run through build-provenance.sh}"
SOURCE_DATE_RFC2822=$(python3 "$REPRO" rfc2822 "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH SOURCE_DATE_RFC2822
pkg=$1; dsc=$2; newv=$3; patch=$4; pname=$5
export HOME=/o/home
D=/o/deb/$pkg-${newv#*:}; rm -rf $D; mkdir -p $D; cd $D; cp /src/${pkg}_* .
dpkg-source -x $dsc >/dev/null
cd ${pkg}-*/
cp /o/patches/$patch debian/patches/$pname; echo $pname >> debian/patches/series
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME="Daniel Campos Ramos"
dch --date "$SOURCE_DATE_RFC2822" -v $newv -D unstable --force-distribution "${DCH_MSG:-Wayland fixes}"
python3 "$REPRO" normalize-tree "$SOURCE_DATE_EPOCH" .
DEB_BUILD_OPTIONS="nocheck parallel=4" dpkg-buildpackage -us -uc >$D.build.log 2>&1; echo build=$?
tail -3 $D.build.log
