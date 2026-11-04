#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/04
# Builds sparky-stereo-wheel-access: the helper the wheel drivers' udev rules run to give the games group their sysfs
# controls, which says through sparky-stereo-problems what it cannot set (ORDER 346f-1). Needs dpkg-deb and
# sparky-stereo-problems; run it in a throwaway container or on any Debian.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.0+lc1
PACKAGE=sparky-stereo-wheel-access
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.wheel-access.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
install -Dm755 "$HERE/bin/sparky-stereo-wheel-access" "$D/usr/lib/udev/sparky-stereo-wheel-access"
sparky-stereo-problems catalog "$PACKAGE" "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL1
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<CONTROL
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: sparky-stereo-problems (>= 0.1.2), udev
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Wheel controls for the games group, and the failure said
  The udev rules of the wheel drivers (new-lg4ff, hid-tmff2, hid-fanatecff) call this
  helper to give the games group the controls their drivers create root-only.
  A control the wheel's model has and that cannot be set is kept by
  sparky-stereo-problems and shown in the session, with Repair; a control the model
  does not have is skipped.
CONTROL
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
if [ "$1" = remove ] && command -v sparky-stereo-problems >/dev/null 2>&1; then
    sparky-stereo-problems clear --all sparky-stereo-wheel-access
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postrm"
(cd "$D" && find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE" --build-dependency sparky-stereo-problems
