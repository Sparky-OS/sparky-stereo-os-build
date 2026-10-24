#!/bin/bash
# Tests of 31-sparky-stereo-ia32.cfg: sourced by sh the way grub-mkconfig sources /etc/default/grub.d, in a fake
# root (firmware size, kernels in /boot, options), and the GRUB_CMDLINE_LINUX and GRUB_CMDLINE_LINUX_DEFAULT it leaves
# (printed as LINUX|DEFAULT) compared with what each case must give. Needs dpkg (dpkg --compare-versions).
#   ia32-hook-tests.sh HOOK
HOOK=$(readlink -f "$1")
pass=0; total=0
mkroot() {   # mkroot FW_PLATFORM_SIZE OPTIONS KERNEL...
	R=$(mktemp -d); mkdir -p "$R/sys/firmware/efi" "$R/etc/default" "$R/boot"
	[ -n "$1" ] && echo "$1" > "$R/sys/firmware/efi/fw_platform_size"
	printf '%b' "$2" > "$R/etc/default/sparky-stereo-boot"
	shift 2
	for k in "$@"; do echo kernel > "$R/boot/vmlinuz-$k"; done
	echo "$R"
}
check() {    # check NAME ROOT PRESET EXPECT_CMDLINE
	total=$((total + 1))
	out=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$2" sh -c "
		GRUB_CMDLINE_LINUX=''; GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'; $3
		. '$HOOK'
		printf '%s|%s' \"\$GRUB_CMDLINE_LINUX\" \"\$GRUB_CMDLINE_LINUX_DEFAULT\"")
	if [ "$out" = "$4" ]; then pass=$((pass + 1)); echo "PASS  $1: $out"; else echo "FAIL  $1: got [$out] want [$4]"; fi
	rm -rf "$2"
}
K11=7.3.0-rc6-stereo3d11; K12=7.3.0-rc6-stereo3d12; DEB=7.2.11+deb14-amd64
check '64-bit UEFI, build 11: unchanged' "$(mkroot 64 '' $K11)" '' '|quiet splash'
check 'BIOS (no fw_platform_size), build 11: unchanged' "$(mkroot '' '' $K11)" '' '|quiet splash'
check '32-bit UEFI, build 11: nokaslr' "$(mkroot 32 '' $K11)" '' ' nokaslr|quiet splash'
check '32-bit UEFI, build 12: KASLR kept' "$(mkroot 32 '' $K12)" '' '|quiet splash'
check '32-bit UEFI, build 12 in all three flavours: KASLR kept' "$(mkroot 32 '' $K12 $K12-v3 7.3.0-rc6-rt-stereo3d12)" '' '|quiet splash'
check '32-bit UEFI, rt build 11 beside base build 12: nokaslr' "$(mkroot 32 '' $K12 7.3.0-rc6-rt-stereo3d11)" '' ' nokaslr|quiet splash'
check '32-bit UEFI, build 12 and build 11: nokaslr while 11 is listed' "$(mkroot 32 '' $K12 $K11)" '' ' nokaslr|quiet splash'
check "32-bit UEFI, build 12 and Debian's kernel: nokaslr" "$(mkroot 32 '' $K12 $DEB)" '' ' nokaslr|quiet splash'
check '32-bit UEFI, build 12 and a dpkg leftover of build 11: KASLR kept' "$(mkroot 32 '' $K12 $K11.dpkg-tmp)" '' '|quiet splash'
check '32-bit UEFI, the build 6 name without a number: nokaslr' "$(mkroot 32 '' 7.3.0-rc1-stereo3d)" '' ' nokaslr|quiet splash'
check '32-bit UEFI, a later base (7.4.0-stereo3d1): KASLR kept' "$(mkroot 32 '' 7.4.0-stereo3d1)" '' '|quiet splash'
check '32-bit UEFI, the 7.3.0 release (stereo3d13): KASLR kept' "$(mkroot 32 '' 7.3.0-stereo3d13)" '' '|quiet splash'
check '32-bit UEFI, no kernel in /boot: unchanged' "$(mkroot 32 '')" '' '|quiet splash'
check '32-bit UEFI, SPARKY_STEREO_IA32_NOKASLR=yes, build 12: nokaslr' "$(mkroot 32 'SPARKY_STEREO_IA32_NOKASLR=yes\n' $K12)" '' ' nokaslr|quiet splash'
check '32-bit UEFI, SPARKY_STEREO_IA32_NOKASLR=no, build 11: unchanged' "$(mkroot 32 'SPARKY_STEREO_IA32_NOKASLR=no\n' $K11)" '' '|quiet splash'
check "the person's nokaslr with build 12: kept" "$(mkroot 32 '' $K12)" "GRUB_CMDLINE_LINUX_DEFAULT='quiet nokaslr splash'" '|quiet nokaslr splash'
check "the person's nokaslr with option no: kept" "$(mkroot 32 'SPARKY_STEREO_IA32_NOKASLR=no\n' $K11)" "GRUB_CMDLINE_LINUX_DEFAULT='quiet nokaslr'" '|quiet nokaslr'
check "the person's nokaslr in GRUB_CMDLINE_LINUX_DEFAULT with build 11: not added twice" "$(mkroot 32 '' $K11)" "GRUB_CMDLINE_LINUX_DEFAULT='quiet nokaslr'" '|quiet nokaslr'
check "the person's nokaslr in GRUB_CMDLINE_LINUX with build 11: not added twice" "$(mkroot 32 '' $K11)" "GRUB_CMDLINE_LINUX='nokaslr'" 'nokaslr|quiet splash'
check 'sourced twice with build 11: nokaslr once' "$(mkroot 32 '' $K11)" "GRUB_CMDLINE_LINUX=' nokaslr'" ' nokaslr|quiet splash'
echo "SUMMARY $pass of $total pass"
[ "$pass" = "$total" ]
