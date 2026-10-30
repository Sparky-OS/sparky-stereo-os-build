#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-grub-l10n: GRUB's menu in the system's language. Debian's GRUB catalogues
# (grub2-common's /usr/share/locale/*/LC_MESSAGES/grub.mo, 2.12 and 2.14 alike) leave out the messages
# of GRUB's shell scripts, so grub-mkconfig writes "Advanced options for ...", "UEFI Firmware Settings"
# and the other entries in English whatever the language; the help text, translated in GRUB itself, is
# not affected. Upstream GRUB's own translations have them (po/*.po of the release tarball). This
# package carries those messages, and only those, for every language upstream translates; at install
# and whenever grub2-common updates a catalogue, Debian's file is diverted to grub.mo.debian and
# grub.mo becomes Debian's messages plus the missing ones (Debian's win where both have one).
# Needs dpkg-deb, gettext (msggrep, msgattrib, msgfmt) and xz; the GRUB release tarball is GRUB_TARBALL
# (downloaded from ftp.gnu.org when absent, checked against its SHA-256).
# Last update 2026/10/30
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparky-stereo-grub-l10n
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
VERSION=$VERSION+lc1
GRUB_VERSION=2.14
GRUB_SHA256=bc8d3c73535b8838d8c8e2654d73edc4e6ae8c8acdb45d5df5dc9a1547446d43
W=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/grub-l10n-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
T=${GRUB_TARBALL:-$W/grub-$GRUB_VERSION.tar.xz}
[ -f "$T" ] || curl -sSfL -o "$T" "https://ftp.gnu.org/gnu/grub/grub-$GRUB_VERSION.tar.xz"
echo "$GRUB_SHA256  $T" | sha256sum -c --quiet
tar -xJf "$T" -C "$W" "grub-$GRUB_VERSION/po" "grub-$GRUB_VERSION/COPYING"
P=$W/grub-$GRUB_VERSION/po
D=$W/$PKG
S=$D/usr/share/$PKG
mkdir -p "$D/DEBIAN" "$S" "$D/usr/lib/$PKG" "$D/usr/share/doc/$PKG"
# the messages whose every source is a shell script of GRUB's (po/POTFILES-shell.in: grub-mkconfig, the
# /etc/grub.d scripts and the other util/*.in tools), translated and not fuzzy
langs=
for po in "$P"/*.po; do
	l=$(basename "$po" .po)
	msggrep --location='util/*.in' --location='util/grub.d/*.in' "$po" 2>/dev/null \
		| msgattrib --translated --no-fuzzy --no-obsolete -o "$W/$l.po" - 2>/dev/null || continue
	grep -q '^msgid "[^"]' "$W/$l.po" || continue
	msgfmt -o "$S/$l.mo" "$W/$l.po"
	langs="$langs $l"
done
langs=${langs# }
echo "$langs" | tr ' ' '\n' >"$S/languages"
install -m 755 "$HERE/lib/merge-mo" "$D/usr/lib/$PKG/merge-mo"

cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
PKG=sparky-stereo-grub-l10n
S=/usr/share/$PKG
merge() {
	for l in $(cat $S/languages); do
		f=/usr/share/locale/$l/LC_MESSAGES/grub.mo
		if ! dpkg-divert --listpackage "$f" | grep -qx $PKG; then
			# only a language Debian ships a GRUB catalogue for
			[ -f "$f" ] || continue
			dpkg-divert --quiet --package $PKG --add --rename --divert "$f.debian" "$f"
		fi
		[ -f "$f.debian" ] || continue
		/usr/lib/$PKG/merge-mo "$f.debian" "$S/$l.mo" "$f" >/dev/null
	done
}
# GRUB's menu written again with the merged messages, so a translation reaches it at once rather than at the next
# update-grub of another package; never in a live session, a chroot or a container (as sparky-stereo-boot's kernel
# keeping), where an image build or the installer writes the menu itself
menu() {
	[ -x /usr/sbin/update-grub ] && [ -e /boot/grub/grub.cfg ] || return 0
	if [ "${SPARKY_STEREO_GRUB_L10N_TEST:-}" != 1 ]; then
		if grep -qw boot=live /proc/cmdline 2>/dev/null || [ -d /run/live ]; then return 0; fi
		if command -v systemd-detect-virt >/dev/null; then
			if systemd-detect-virt --quiet --chroot || systemd-detect-virt --quiet --container; then return 0; fi
		fi
		if [ -e /.dockerenv ] || [ -e /run/.containerenv ] || [ ! -d /run/systemd/system ]; then return 0; fi
	fi
	update-grub || true
}
case "$1" in
	configure|triggered)
		merge
		menu
	;;
esac
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
# postrm script
set -e
PKG=sparky-stereo-grub-l10n
if [ "$1" = "remove" ] || [ "$1" = "purge" ] || [ "$1" = "abort-install" ]; then
	for f in $(dpkg-divert --list "/usr/share/locale/*/LC_MESSAGES/grub.mo" | awk -v p=$PKG '$NF == p {print $3}'); do
		rm -f "$f"
		dpkg-divert --quiet --package $PKG --remove --rename --divert "$f.debian" "$f"
	done
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
# grub2-common's catalogues: the path as grub2-common lists it, and the diverted one
for l in $langs; do
	printf 'interest-noawait /usr/share/locale/%s/LC_MESSAGES/grub.mo\ninterest-noawait /usr/share/locale/%s/LC_MESSAGES/grub.mo.debian\n' "$l" "$l"
done >"$D/DEBIAN/triggers"

cp "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Files: usr/lib/sparky-stereo-grub-l10n/* DEBIAN/*
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3+

Files: usr/share/sparky-stereo-grub-l10n/*.mo
    Messages of GRUB's shell scripts from GNU GRUB's translations (po/*.po of the GRUB release
    tarball, https://ftp.gnu.org/gnu/grub/), made by the Translation Project's translators; each
    language's translators are named in the header of its catalogue.
    Copyright (C) Free Software Foundation, Inc.
    License: GPL-3+

License: GPL-3+
    This package is free software; you can redistribute it and/or modify it under the terms of the
    GNU General Public License as published by the Free Software Foundation; either version 3 of the
    License, or (at your option) any later version.
    On Debian systems, the complete text of the GNU General Public License can be found in
    `/usr/share/common-licenses/GPL-3'.
EOS
find "$D" -path "$D/DEBIAN" -prune -o -type d -exec chmod 755 {} +
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: grub2-common, python3
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: GRUB's menu in the system's language
  Debian's GRUB catalogues leave out the messages of GRUB's shell
  scripts, so the menu that grub-mkconfig writes ("Advanced options for
  ...", "UEFI Firmware Settings" and the others) stays in English. This
  package adds those messages from GNU GRUB's own translations to
  Debian's catalogues, and adds them again whenever GRUB updates; GRUB's
  menu is then written again, so the translation reaches it at once.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
mkdir -p "$W/authoring"
cp -a "$HERE/." "$W/authoring/"
cp -a "$P" "$W/authoring/upstream-po"
cp "$W/grub-$GRUB_VERSION/COPYING" "$W/authoring/COPYING.grub"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$W/authoring"
echo "built $PKG with $(echo $langs | wc -w) languages"
