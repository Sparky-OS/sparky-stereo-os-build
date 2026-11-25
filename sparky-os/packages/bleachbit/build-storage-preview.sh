#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Run in a Debian build container with bleachbit's Build-Depends installed.
set -eu
: "${SOURCE_DATE_EPOCH:?}" "${OUT:?}"
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(CDPATH= cd -- "$here/../.." && pwd)
source_archive=$(realpath "${1:?Supply the directory with the Debian 6.0.6-1 source closure}")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
export DEBEMAIL=Capitain_Jack@yahoo.com DEBFULLNAME='Daniel Ramos (Capitain Jack)'
cd "$work"
dsc=bleachbit_6.0.6-1.dsc
printf '%s  %s\n' 53ebb1676def6c97ed731439016f91447e25e96544eeae3a6d48e3a078990907 "$source_archive/$dsc" | sha256sum -c
cp -- "$source_archive/$dsc" "$source_archive/bleachbit_6.0.6-1.debian.tar.xz" .
cp -- "$source_archive/bleachbit_6.0.6.orig.tar.gz" "$source_archive/bleachbit_6.0.6.orig.tar.gz.asc" .
dpkg-source -x "$dsc" source
cd source
cp -- "$here/patches/structured-preview.patch" debian/patches/
printf '%s\n' structured-preview.patch >> debian/patches/series
dpkg-source --before-build .
date=$(date -Ru -d "@$SOURCE_DATE_EPOCH")
cat > "$work/entry" <<EOF
bleachbit (6.0.6-1+stereo3d1) unstable; urgency=medium

  * Expose reviewed cleanup items on a selected Linux volume.

 -- $DEBFULLNAME <$DEBEMAIL>  $date

EOF
cat "$work/entry" debian/changelog > "$work/changelog"
mv -- "$work/changelog" debian/changelog
python3 "$toolkit/repo/reproducible.py" normalize-tree "$SOURCE_DATE_EPOCH" .
case "${2:-}" in
    --plain|--source-only) ;;
    ''|--lean-source-only) PYTHONPATH="$toolkit" python3 -m lean.debian_prepare . 6.0.6-1+stereo3d1+lc1 --toolkit "$toolkit" ;;
    *) exit 2 ;;
esac
case "${2:-}" in
    --source-only|--lean-source-only) dpkg-source -b . ;;
    *) dpkg-buildpackage -us -uc -j4 ;;
esac
mkdir -p -- "$OUT"
for artifact in ../bleachbit_*; do
    case "$artifact" in
        *+stereo3d1*|*.orig.tar.gz|*.orig.tar.gz.asc) cp -- "$artifact" "$OUT/" ;;
    esac
done
