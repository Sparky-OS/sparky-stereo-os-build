#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# repack.sh OLD.deb OLD-RELEASE NEW-RELEASE OUT.deb : the same package for another release name (names only; the
# payload bytes are untouched), for install/upgrade/removal tests of the maintainer scripts. Run as root in a container.
set -eu
deb=$1; old=$2; new=$3; out=$4
t=$(mktemp -d)
dpkg-deb -R "$deb" "$t/p"
# directories and files named after the release
find "$t/p" -depth -name "*$old*" | while read -r f; do
    d=$(dirname "$f"); b=$(basename "$f"); mv "$f" "$d/$(echo "$b" | sed "s/$old/$new/g")"
done
# text that names the release: control, maintainer scripts, symlink targets stay (they name the old path only for headers)
sed -i "s/$old/$new/g" "$t/p/DEBIAN/control"
for s in preinst postinst prerm postrm; do [ -f "$t/p/DEBIAN/$s" ] && sed -i "s/$old/$new/g" "$t/p/DEBIAN/$s"; done
(cd "$t/p" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum > DEBIAN/md5sums)
dpkg-deb --root-owner-group -Znone -b "$t/p" "$out" >/dev/null
rm -rf "$t"
