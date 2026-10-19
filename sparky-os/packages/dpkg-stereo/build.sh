#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the MIT License
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# Builds dpkg-stereo: Lean Code for installed packages (sparky-os/LEAN-CODE-POLICY.md, "Install-time
# projection: dpkg-stereo"). It carries the lean package (sparky-os/lean, the MR/HR compiler ported from
# CGM) in /usr/lib/dpkg-stereo, dpkg's pre-invoke and post-invoke hooks, the first-update hook that writes
# the HR copies of settings, and the pre-squashfs hook Sparky Backup Core Stereo runs for the ISO.
# Needs only dpkg-deb; run it in a throwaway container or on any Debian.
# Last update 2026/10/17
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
LEAN=$(cd "$HERE/../../lean" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
VERSION=0.1.7
PKG=dpkg-stereo
W=$(mktemp -d "${TMPDIR:-/K3D/temp}/dpkg-stereo-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/sbin" "$D/usr/lib/dpkg-stereo/lean" "$D/etc/dpkg/dpkg.cfg.d" "$D/etc/apt/apt.conf.d" \
	"$D/usr/share/doc/$PKG"
install -m 755 "$HERE/bin/dpkg-stereo" "$D/usr/sbin/dpkg-stereo"
install -m 755 "$HERE/lib/presquashfs-hook" "$D/usr/lib/dpkg-stereo/presquashfs-hook"
install -m 644 "$LEAN"/*.py "$LEAN/JvmLexer.java" "$D/usr/lib/dpkg-stereo/lean/"
install -m 644 "$HERE/etc/dpkg-stereo.cfg" "$D/etc/dpkg/dpkg.cfg.d/dpkg-stereo"
install -m 644 "$HERE/etc/99dpkg-stereo-hr" "$D/etc/apt/apt.conf.d/99dpkg-stereo-hr"
install -m 644 "$HERE/copyright" "$D/usr/share/doc/$PKG/copyright"
printf '/etc/apt/apt.conf.d/99dpkg-stereo-hr\n/etc/dpkg/dpkg.cfg.d/dpkg-stereo\n' >"$D/DEBIAN/conffiles"
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
if [ "$1" = "configure" ] && [ -z "${DPKG_STEREO_NO_PROJECT:-}" ]; then
	# dpkg read its hooks before this run, so the first projection of the installed packages is made here;
	# an upgrade finds them recorded already, and its own post-invoke run takes only what it changed
	if [ -z "${2:-}" ] || [ ! -e /var/lib/dpkg-stereo/packages.tsv ]; then
		/usr/sbin/dpkg-stereo --project || true
	fi
fi
exit 0
EOS
cat >"$D/DEBIAN/prerm" <<'EOS'
#!/bin/sh
# prerm script
set -e
if [ "$1" = "remove" ]; then
	# the way back: the original files return (conffiles from the record, other files from their packages)
	/usr/sbin/dpkg-stereo --restore || true
	# without the package table a later install projects everything again
	rm -f /var/lib/dpkg-stereo/packages.tsv
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
if [ "$1" = "purge" ]; then
	rm -rf /var/lib/dpkg-stereo
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: dpkg, python3
Recommends: gcc, node-acorn, nodejs, perl, python3-yaml
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Lean Code for installed packages
  Sparky Stereo OS keeps the packages of every source as they were built and
  projects the text files they install (scripts, QML and JavaScript, settings,
  units and rules, headers) into their machine form, without the comments the
  machine never reads. Each projection is checked by the file's own reader,
  recorded and reversible; settings edited by the person are never touched,
  and dpkg never asks about a projected setting.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | grep -v '^etc/' | sort | xargs md5sum) >"$D/DEBIAN/md5sums"
mkdir -p "$OUT"
"$HERE/../../repo/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
