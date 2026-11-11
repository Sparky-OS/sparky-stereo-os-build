#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/10
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/06
#
# /tmp on disk, as root in a disposable container: the package's maintainer
# scripts (DEB = the built package) mask tmp.mount once and leave an
# administrator's choice alone, and ship no /tmp rule: /tmp keeps its files across
# boots (Daniel, 2026-11-02: "I never asked for a wipe"), and ship /etc/tmpfiles.d/tmp.conf, which keeps them
# between boots too: no age cleanup (Daniel, 2026-11-06: "make sure the tmp cleaner is really off").
# OLD = the previously published package, installed in the container (the upgrade proof); datefudge moves the clock (libfaketime would shift the files' own times too).
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
# /tmp's files, and with the package's own tmpfiles.d files added it still does.
boot() {
	local root=$W/root-$1
	mkdir -p "$root/usr/lib/tmpfiles.d" "$root/tmp"
	cp /usr/lib/tmpfiles.d/tmp.conf "$root/usr/lib/tmpfiles.d/tmp.conf"
	[[ $1 == package ]] && cp "$W"/data/usr/lib/tmpfiles.d/*.conf "$root/usr/lib/tmpfiles.d/"
	echo left >"$root/tmp/from-last-boot"
	systemd-tmpfiles --root="$root" --create --remove --boot >"$OUT/tmpfiles-$1.log" 2>&1
	[[ -e $root/tmp/from-last-boot ]] && echo kept || echo removed
}
check control-debian-tmp-conf-keeps-files "$(boot debian)" kept
check package-keeps-tmp-at-boot "$(boot package)" kept
check package-ships-no-tmp-rule "$(ls "$W/data/usr/lib/tmpfiles.d/sparky-tmp.conf" 2>/dev/null || echo none)" none
check tmp-conf-is-a-conffile "$(grep -cx /etc/tmpfiles.d/tmp.conf "$W/control/conffiles")" 1

# systemd-tmpfiles --clean on a fixture root whose clock is 11 days ahead: Debian's file alone ages /tmp out after 10 days
# (the red control), the package keeps everything in /tmp and still cleans /var/tmp after 30 days.
clean() {
	local root=$W/clean-$1
	mkdir -p "$root/usr/lib/tmpfiles.d" "$root/etc/tmpfiles.d" "$root/tmp" "$root/var/tmp"
	cp /usr/lib/tmpfiles.d/tmp.conf "$root/usr/lib/tmpfiles.d/tmp.conf"
	[[ $1 == package ]] && cp "$W/data/etc/tmpfiles.d/tmp.conf" "$root/etc/tmpfiles.d/tmp.conf"
	echo old >"$root/tmp/untouched-11-days"
	echo old >"$root/var/tmp/untouched-11-days"
	mkdir -p "$root/tmp/dir"
	echo old >"$root/tmp/dir/inside"
	datefudge '11 days' systemd-tmpfiles --root="$root" --clean >"$OUT/clean-$1.log" 2>&1
	local r=""
	[[ -e $root/tmp/untouched-11-days ]] && r+=tmp-kept || r+=tmp-removed
	[[ -e $root/tmp/dir/inside ]] && r+=,subdir-kept || r+=,subdir-removed
	[[ -e $root/var/tmp/untouched-11-days ]] && r+=,vartmp-kept || r+=,vartmp-removed
	echo "$r"
}
check control-debian-alone-ages-out-tmp "$(clean debian)" tmp-removed,subdir-removed,vartmp-kept
check package-tmp-kept-11-days "$(clean package)" tmp-kept,subdir-kept,vartmp-kept
vt=$W/clean-vartmp
mkdir -p "$vt/usr/lib/tmpfiles.d" "$vt/etc/tmpfiles.d" "$vt/var/tmp" "$vt/tmp"
cp /usr/lib/tmpfiles.d/tmp.conf "$vt/usr/lib/tmpfiles.d/tmp.conf"
cp "$W/data/etc/tmpfiles.d/tmp.conf" "$vt/etc/tmpfiles.d/tmp.conf"
echo old >"$vt/var/tmp/old" ; echo old >"$vt/tmp/old"
datefudge '31 days' systemd-tmpfiles --root="$vt" --clean >"$OUT/clean-vartmp.log" 2>&1
check package-vartmp-still-30-days "$([[ -e $vt/var/tmp/old ]] && echo kept || echo removed),$([[ -e $vt/tmp/old ]] && echo kept || echo removed)" removed,kept
dry=$(SYSTEMD_LOG_LEVEL=debug datefudge '11 days' systemd-tmpfiles --root="$W/clean-package" --clean --dry-run 2>&1)
echo old >"$W/clean-debian/tmp/again"
check control-dry-run-lists-debian-clean "$(datedry=$(SYSTEMD_LOG_LEVEL=debug datefudge '11 days' systemd-tmpfiles --root="$W/clean-debian" --clean --dry-run 2>&1); grep -c 'Would remove .*/tmp/' <<<"$datedry" | sed 's/^[1-9].*/lists/')" lists
check dry-run-lists-nothing-under-tmp "$(grep -c 'Would remove .*/tmp/' <<<"$dry")" 0
cfg=$(systemd-tmpfiles --root="$W/clean-package" --cat-config 2>&1)
check effective-tmp-rule "$(grep -c '^q /tmp 1777 root root -$' <<<"$cfg")" 1
check debian-tmp-rule-shadowed "$(grep -c '^q /tmp 1777 root root 10d' <<<"$cfg")" 0
check effective-vartmp-rule "$(grep -c '^q /var/tmp 1777 root root 30d$' <<<"$cfg")" 1
grep -h "^[^#]" /usr/lib/tmpfiles.d/tmp.conf "$W"/data/usr/lib/tmpfiles.d/*.conf >"$OUT/tmpfiles-lines.txt"
# The upgrade from the published package, with apt's and dpkg's own conffile rules (OLD installed; DEB upgrades it).
if [[ -n ${OLD:-} ]]; then
	cf=/etc/tmpfiles.d/tmp.conf
	rm -f "$cf"
	dpkg -i "$DEB" >"$OUT/upgrade-fresh.log" 2>&1 </dev/null
	check upgrade-installs-conffile "$(cmp -s "$cf" "$W/data$cf" && echo same || echo differs)" same
	# The station's own file (identical text) is adopted with no prompt.
	dpkg -r sparky-stereo-kernel-settings >/dev/null 2>&1 </dev/null || true
	dpkg -P sparky-stereo-kernel-settings >/dev/null 2>&1 </dev/null || true
	dpkg -i "$OLD" >"$OUT/old-install.log" 2>&1 </dev/null
	check old-version-ships-no-conffile "$([ -e $cf ] && echo yes || echo no)" no
	cp "$W/data$cf" "$cf"
	dpkg -i "$DEB" >"$OUT/upgrade-identical.log" 2>&1 </dev/null
	check identical-file-adopted-without-prompt "$(grep -c 'Configuration file' "$OUT/upgrade-identical.log")" 0
	# A person's own edit is kept: the same package again, and a later package whose file changed.
	printf '# my choice\nq /tmp 1777 root root 90d\n' >"$cf"
	dpkg -i "$DEB" >"$OUT/upgrade-same.log" 2>&1 </dev/null
	check edit-kept-on-reinstall "$(grep -c 90d "$cf")" 1
	mkdir -p "$W/next"
	dpkg-deb -R "$DEB" "$W/next"
	printf '# a later release\n' >>"$W/next$cf"
	new_md5=$(md5sum "$W/next$cf" | cut -d' ' -f1)
	sed -i "s|^[0-9a-f]*  etc/tmpfiles.d/tmp.conf|$new_md5  etc/tmpfiles.d/tmp.conf|" "$W/next/DEBIAN/md5sums"
	sed -i 's/^Version: .*/Version: 20261106.2~sparky9~0+lc1/' "$W/next/DEBIAN/control"
	dpkg-deb -b "$W/next" "$W/next.deb" >/dev/null
	dpkg -i --force-confdef --force-confold "$W/next.deb" >"$OUT/upgrade-next.log" 2>&1 </dev/null
	check edit-kept-on-later-upgrade "$(grep -c 90d "$cf")" 1
	check later-upgrade-reports-the-kept-file "$([[ $(grep -c "Configuration file" "$OUT/upgrade-next.log") -ge 1 ]] && echo reported || echo silent)" reported
	# A file the person did not edit follows the package.
	dpkg -P sparky-stereo-kernel-settings >/dev/null 2>&1 </dev/null
	dpkg -i "$DEB" >/dev/null 2>&1 </dev/null
	dpkg -i --force-confdef --force-confold "$W/next.deb" >"$OUT/upgrade-untouched.log" 2>&1 </dev/null
	check unedited-file-follows-package "$(grep -c 'a later release' "$cf")" 1
fi
echo "SUMMARY: $PASS passed, $FAIL failed" | tee "$OUT/summary.txt"
chown -R "${OWNER:-1000:1000}" "$OUT"
((FAIL == 0))
