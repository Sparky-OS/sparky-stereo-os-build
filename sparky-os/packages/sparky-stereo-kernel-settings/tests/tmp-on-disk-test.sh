#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
#
# /tmp on disk, as root in a disposable container: the package's maintainer
# scripts (DEB = the built package) mask tmp.mount once and leave an
# administrator's choice alone; systemd-tmpfiles applies the package's
# D line before systemd's own tmp.conf and so empties /tmp at boot.
set -u
DEB=${DEB:?built package}
OUT=${OUT:?results folder}
mkdir -p "$OUT"
W=$(mktemp -d)
PASS=0 FAIL=0
check() {
	if [[ $2 == "$3" ]]; then echo "PASS $1"; PASS=$((PASS + 1)); else echo "FAIL $1: got '$2', expected '$3'"; FAIL=$((FAIL + 1)); fi
}
dpkg-deb -e "$DEB" "$W/control"
dpkg-deb -x "$DEB" "$W/data"
unit=/etc/systemd/system/tmp.mount
mark=/var/lib/sparky-stereo-kernel-settings/tmp-mount-masked
rm -f "$unit" "$mark"

sh "$W/control/postinst" configure ""
check fresh-install-masks "$(readlink "$unit")" /dev/null
check fresh-install-marks "$([ -e $mark ] && echo yes)" yes
systemctl unmask tmp.mount >/dev/null 2>&1 || rm -f "$unit"
sh "$W/control/postinst" configure 20261010.2~sparky9~0
check upgrade-keeps-unmask "$(readlink "$unit" || echo none)" none
rm -f "$unit" "$mark"
printf '[Mount]\nWhat=tmpfs\n' >"$unit"
sh "$W/control/postinst" configure 20261010.1~sparky9~0
check admin-unit-untouched "$(head -1 "$unit")" "[Mount]"
check admin-unit-no-mark "$([ -e $mark ] && echo yes || echo no)" no
rm -f "$unit"
sh "$W/control/postinst" configure 20261010.1~sparky9~0
check upgrade-from-older-masks "$(readlink "$unit")" /dev/null
sh "$W/control/postrm" purge
check purge-removes-own-mask "$(readlink "$unit" || echo none)" none

# systemd-tmpfiles at boot on a fixture root: Debian's tmp.conf (systemd 262: "Q /tmp 1777 root root 10d") alone keeps
# /tmp's files; with the package's sparky-tmp.conf, the boot run empties /tmp.
boot() {
	local root=$W/root-$1
	mkdir -p "$root/usr/lib/tmpfiles.d" "$root/tmp"
	cp /usr/lib/tmpfiles.d/tmp.conf "$root/usr/lib/tmpfiles.d/tmp.conf"
	[[ $1 == package ]] && cp "$W/data/usr/lib/tmpfiles.d/sparky-tmp.conf" "$root/usr/lib/tmpfiles.d/"
	echo left >"$root/tmp/from-last-boot"
	systemd-tmpfiles --root="$root" --create --remove --boot >"$OUT/tmpfiles-$1.log" 2>&1
	[[ -e $root/tmp/from-last-boot ]] && echo kept || echo removed
}
check control-debian-tmp-conf-keeps-files "$(boot debian)" kept
check package-empties-tmp-at-boot "$(boot package)" removed
grep -h "^[^#]" /usr/lib/tmpfiles.d/tmp.conf "$W/data/usr/lib/tmpfiles.d/sparky-tmp.conf" >"$OUT/tmpfiles-lines.txt"
echo "SUMMARY: $PASS passed, $FAIL failed" | tee "$OUT/summary.txt"
chown -R "${OWNER:-1000:1000}" "$OUT"
((FAIL == 0))
