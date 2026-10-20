#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/14
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/14
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=0.1.0+lc1
PACKAGE=sparky-stereo-user-groups
DEPENDS='adduser, coreutils, gawk | mawk, grep, libc-bin, sed'
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.user-groups.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
install -Dm644 "$HERE/etc/sparky-stereo/user-groups" "$D/etc/sparky-stereo/user-groups"
install -Dm755 "$HERE/usr/sbin/sparky-stereo-user-groups" "$D/usr/sbin/sparky-stereo-user-groups"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -m644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOT
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Groups every desktop user needs, by default
  New users get games, dialout, plugdev, audio, video, bluetooth, netdev,
  lpadmin, scanner, kvm, render and sambashare, whether the installer,
  adduser or System Settings creates them. Groups that equal root or read every
  keystroke are refused.
EOT
printf '%s\n' /etc/sparky-stereo/user-groups >"$D/DEBIAN/conffiles"
echo 'interest-noawait /usr/share/calamares/modules' >"$D/DEBIAN/triggers"
cat >"$D/DEBIAN/postinst" <<'EOT'
#!/bin/sh
set -e
case "$1" in
	configure|triggered)
		/usr/sbin/sparky-stereo-user-groups apply || echo "sparky-stereo-user-groups: the groups were not applied, see above" >&2
		;;
esac
EOT
cat >"$D/DEBIAN/prerm" <<'EOT'
#!/bin/sh
set -e
case "$1" in
	remove|deconfigure)
		/usr/sbin/sparky-stereo-user-groups remove || true
		;;
esac
EOT
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"

sync
