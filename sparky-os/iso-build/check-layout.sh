#!/bin/sh
# Created by Daniel Ramos (Capitain Jack) 2026/11/16 (ORDER 614; lane 597 found the guard missing)
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/16
# The USB stick's layout of a packed ISO, read from xorriso -indev ISO -report_system_area plain: an isohybrid MBR with its
# active partition 1 at LBA 64, the 0xef partition that is the EFI image, the GPT, and the Apple partition map that Apple's
# firmware reads to list the stick (xorrisofs(1): the APM "is read by Macs for booting and for mounting"; the packer's
# -isohybrid-mbr, -partition_offset 16, -isohybrid-gpt-basdat and -isohybrid-apm-hfsplus produce them). A packer that
# loses one of them gives an ISO that boots on PCs and is invisible to a Mac, and nothing else catches it (Apple's
# firmware is not in the boot matrix). Prints PASS or FAIL per check, what is missing and what to do; exits 1 on any FAIL.
#   check-layout.sh ISO
#   check-layout.sh --report FILE   (a saved report, for tests)
set -u
if [ "${1:-}" = --report ]; then
	[ -r "${2:-}" ] || { echo "FAIL  cannot read the report ${2:-}"; exit 1; }
	REPORT=$2
else
	ISO=${1:?usage: check-layout.sh ISO}
	REPORT=$(mktemp) || exit 1
	trap 'rm -f "$REPORT"' EXIT
	if ! xorriso -indev "$ISO" -report_system_area plain >"$REPORT" 2>&1; then
		cat "$REPORT"
		echo "FAIL  xorriso cannot read the system area of $ISO (is xorriso installed, is the file an ISO?)"
		exit 1
	fi
fi
awk '
function ok(s)  { print "PASS  " s }
function no(s)  { print "FAIL  " s; fails++ }
/^System area summary:/ { summary = $0 }
/^MBR partition +:/ { n = $4; status[n] = $5; type[n] = $6; start[n] = $7; mbr_count++ }
/^MBR partition path +:/ { mbrpath[$5] = $6 }
/^GPT partition path +:/ { gptpath[$5] = $6; gpt_paths++ }
/^APM partition type +:/ { apmtype[$5] = $6 }
/^APM partition path +:/ { apmpath[$5] = $6 }
END {
	if (summary ~ /MBR isohybrid/) ok("the system area is an isohybrid MBR (" summary ")"); else no("the system area is not an isohybrid MBR: the stick would not boot on a PC from BIOS (the packer lost -isohybrid-mbr)")
	if (summary ~ /GPT/) ok("a GPT is written"); else no("no GPT in the system area: UEFI firmware lists no EFI partition on the stick (the packer lost -isohybrid-gpt-basdat)")
	if (summary ~ /APM/) ok("an Apple partition map is written"); else no("no Apple partition map in the system area: Apple firmware does not list the stick under Option (the packer lost -isohybrid-apm-hfsplus)")
	if (status[1] == "0x80" && start[1] == 64) ok("MBR partition 1 is active and starts at LBA 64"); else no("MBR partition 1 is not active at LBA 64 (status " status[1] ", start " start[1] "): the ISO was made without -partition_offset 16 or with another isohybrid MBR")
	efi = 0
	for (i in type) if (type[i] == "0xef" && mbrpath[i] ~ /efi\.img$/) efi = i
	if (efi) ok("MBR partition " efi " is type 0xef and is the EFI image (" mbrpath[efi] ")"); else no("no MBR partition of type 0xef that is the EFI image: a PC in UEFI mode finds no ESP on the stick (the packer lost -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot)")
	gpt = 0
	for (i in gptpath) if (gptpath[i] ~ /efi\.img$/) gpt = i
	if (gpt) ok("a GPT partition is the EFI image (" gptpath[gpt] ")"); else no("no GPT partition is the EFI image")
	apm = 0
	for (i in apmtype) if (apmtype[i] == "Apple_HFS" && apmpath[i] ~ /efi\.img$/) apm = i
	if (apm) ok("APM partition " apm " is Apple_HFS and is the EFI image (" apmpath[apm] ")"); else no("no Apple_HFS APM partition that is the EFI image: Apple firmware has nothing to start (the packer lost -isohybrid-apm-hfsplus)")
	exit fails ? 1 : 0
}' "$REPORT"
