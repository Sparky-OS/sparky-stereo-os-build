#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/16 (ORDER 614)
# Copyright 2026 under the GNU GPL3 License
# check-layout.sh against small ISOs made with the packer's literal xorriso options (sparkybackup, /usr/bin/sparkybackup
# line 1323): green for the whole command, red for each option left out. Needs xorriso, isolinux and syslinux-utils (the
# build image has them); run in a container. Usage: test-check-layout.sh
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/T/isolinux" "$T/T/boot/grub" "$T/T/EFI/boot"
cp /usr/lib/ISOLINUX/isolinux.bin "$T/T/isolinux/"
echo x > "$T/T/EFI/boot/bootx64.efi"
head -c 2097152 /dev/zero > "$T/T/boot/grub/efi.img"
fails=0
make_iso() { # NAME EXTRA_OPTIONS
	name=$1; shift
	xorriso -as mkisofs -R -r -J -joliet-long -l -iso-level 3 -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -partition_offset 16 \
		-V TEST -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table \
		-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot "$@" -o "$T/$name.iso" "$T/T" >/dev/null 2>&1 || { echo "FAIL  could not make $name.iso"; fails=$((fails + 1)); }
}
expect() { # NAME green|red [TEXT that must be in the output]
	sh "$HERE/check-layout.sh" "$T/$1.iso" >"$T/$1.out" 2>&1; rc=$?
	if [ "$2" = green ]; then
		if [ $rc = 0 ] && ! grep -q '^FAIL' "$T/$1.out"; then echo "PASS  $1: the check passes"; else echo "FAIL  $1: the check should pass"; cat "$T/$1.out"; fails=$((fails + 1)); fi
	else
		if [ $rc != 0 ] && grep -q "^FAIL.*$3" "$T/$1.out"; then echo "PASS  $1: the check fails, naming '$3'"; else echo "FAIL  $1: the check should fail naming '$3' (exit $rc)"; cat "$T/$1.out"; fails=$((fails + 1)); fi
	fi
}
make_iso packer -isohybrid-gpt-basdat -isohybrid-apm-hfsplus
make_iso no-apm -isohybrid-gpt-basdat
make_iso no-gpt -isohybrid-apm-hfsplus
make_iso bare
expect packer green
expect no-apm red 'no Apple partition map'
expect no-apm red 'no Apple_HFS APM partition'
expect no-gpt red 'no GPT'
expect bare red 'no Apple partition map'
# a file that is not an ISO: xorriso reads it without error and reports no boot structure, which fails every check
echo not an iso > "$T/junk.iso"
expect junk red 'not an isohybrid MBR'
# a saved report with MBR partition 1 not active
xorriso -indev "$T/packer.iso" -report_system_area plain 2>&1 | sed 's/^\(MBR partition      :   1 \)  0x80/\1  0x00/' > "$T/inactive.report"
sh "$HERE/check-layout.sh" --report "$T/inactive.report" >"$T/inactive.out" 2>&1; rc=$?
if [ $rc != 0 ] && grep -q '^FAIL.*MBR partition 1 is not active' "$T/inactive.out"; then echo "PASS  an inactive MBR partition 1 is caught"; else echo "FAIL  an inactive MBR partition 1 should be caught"; cat "$T/inactive.out"; fails=$((fails + 1)); fi
echo "== $([ $fails = 0 ] && echo ALL PASS || echo "$fails FAILED")"
[ $fails = 0 ]
