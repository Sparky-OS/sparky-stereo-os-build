#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.0+lc1
PACKAGE=sparky-stereo-vram-boost
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.vram-boost.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
install -Dm755 "$HERE/bin/sparky-stereo-vram-boost" "$D/usr/lib/sparky-stereo-vram-boost/sparky-stereo-vram-boost"
install -Dm644 "$HERE/share/systemd/sparky-stereo-vram-boost.service" "$D/usr/lib/systemd/system/sparky-stereo-vram-boost.service"
mkdir -p "$D/usr/lib/systemd/system/multi-user.target.wants"
ln -s ../sparky-stereo-vram-boost.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-vram-boost.service"
install -Dm644 "$HERE/share/systemd/dmemcg-booster-system.conf" "$D/usr/lib/systemd/system/dmemcg-booster-system.service.d/sparky-stereo-vram-boost.conf"
for unit in dmemcg-booster-user plasma-foreground-booster; do
	install -Dm644 "$HERE/share/systemd/user.conf" "$D/usr/lib/systemd/user/$unit.service.d/sparky-stereo-vram-boost.conf"
done
install -Dm644 "$HERE/share/default/sparky-stereo-vram-boost" "$D/etc/default/sparky-stereo-vram-boost"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<CONTROL
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: bash, dmemcg-booster, systemd
Recommends: plasma-foreground-booster
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Decide at every boot whether the window in front gets VRAM protection
  Starts dmemcg-booster and plasma-foreground-booster only where they help:
  a kernel with the dmem cgroup controller and an AMD GPU with its own VRAM.
  SPARKY_STEREO_VRAM_BOOST=auto, yes or no in its /etc/default file.
CONTROL
echo /etc/default/sparky-stereo-vram-boost >"$D/DEBIAN/conffiles"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
