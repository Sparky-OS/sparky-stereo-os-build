#!/bin/bash
# Tests of 30-sparky-stereo-boot.cfg: sourced the way grub-mkconfig sources /etc/default/grub.d,
# in a fake root, and the GRUB_* values it leaves compared with what each case must give.
#   grub-hook-tests.sh HOOK FIXTURES
HOOK=$(readlink -f "$1"); FIX=$(readlink -f "$2")
pass=0; total=0
mkroot() {   # mkroot CONNECTOR EDIDFILE [OPTIONS] [GRUBVARS]
	R=$(mktemp -d); mkdir -p "$R/sys/class/drm/card0-$1" "$R/etc/default" "$R/var/lib/sparky-stereo-boot" "$R/fonts"
	echo connected > "$R/sys/class/drm/card0-$1/status"; cp "$2" "$R/sys/class/drm/card0-$1/edid"
	printf '%b' "${3:-}" > "$R/etc/default/sparky-stereo-boot"
	[ -n "${4:-}" ] && printf '%b' "$4" > "$R/var/lib/sparky-stereo-boot/grub.cfg"
	echo "$R"
}
check() {    # check NAME ROOT PRESET EXPECT_GFXMODE EXPECT_PAYLOAD EXPECT_CMDLINE EXPECT_FONT_BASENAME
	total=$((total + 1))
	out=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$2" SPARKY_FONT_DIR="$2/fonts" bash -c "
		GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'; $3
		. '$HOOK'
		printf '%s|%s|%s|%s' \"\$GRUB_GFXMODE\" \"\$GRUB_GFXPAYLOAD_LINUX\" \"\$GRUB_CMDLINE_LINUX_DEFAULT\" \"\${GRUB_FONT##*/}\"")
	want="$4|$5|$6|$7"
	if [ "$out" = "$want" ]; then pass=$((pass + 1)); echo "PASS  $1: $out"; else echo "FAIL  $1: got [$out] want [$want]"; fi
	rm -rf "$2"
}
CMD='quiet splash ${sparky_stereo_boot}'
check 'saved 3D mode on the TV (1920x1080 base)' "$(mkroot HDMI-A-1 $FIX/hx855.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\nSPARKY_STEREO_CONNECTOR=HDMI-A-1\n')" '' \
	'1920x1080,1280x720,1024x768,auto' keep "$CMD" ''
check 'saved 1280x800 on the VM screen' "$(mkroot Virtual-1 $FIX/qemu-stereo.edid '' 'SPARKY_STEREO_GFXMODE=1280x800\nSPARKY_STEREO_CONNECTOR=Virtual-1\n')" '' \
	'1280x800,1920x1080,1280x720,1024x768,auto' keep "$CMD" ''
check 'no saved choice: the EDID native mode (study)' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" '' \
	'1920x1080,1280x720,1024x768,auto' keep "$CMD" ''
check 'the person set GRUB_GFXMODE: kept' "$(mkroot HDMI-A-1 $FIX/hx855.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\n')" 'GRUB_GFXMODE=1024x768' \
	'1024x768' keep "$CMD" ''
check 'the person set GRUB_GFXPAYLOAD_LINUX: kept' "$(mkroot HDMI-A-1 $FIX/hx855.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\n')" 'GRUB_GFXPAYLOAD_LINUX=text' \
	'1920x1080,1280x720,1024x768,auto' text "$CMD" ''
check 'SPARKY_STEREO_BOOT=no: GRUB as it was' "$(mkroot HDMI-A-1 $FIX/hx855.edid 'SPARKY_STEREO_BOOT=no\n' 'SPARKY_STEREO_GFXMODE=1920x1080\n')" '' \
	'' '' 'quiet splash' ''
check 'SPARKY_STEREO_GRUB=auto: resolution left to the firmware' "$(mkroot HDMI-A-1 $FIX/hx855.edid 'SPARKY_STEREO_GRUB=auto\n' 'SPARKY_STEREO_GFXMODE=1920x1080\n')" '' \
	'' keep "$CMD" ''
check 'sourced twice: the kernel variable added once' "$(mkroot HDMI-A-1 $FIX/hx855.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\n')" "GRUB_CMDLINE_LINUX_DEFAULT='quiet splash \${sparky_stereo_boot}'" \
	'1920x1080,1280x720,1024x768,auto' keep "$CMD" ''
# a 15.6 inch UHD laptop panel (344 x 193 mm) saved at 3840x2160 and at 1920x1080: the font follows the width shown
python3 - "$FIX/hx855.edid" /tmp/uhd-panel.edid <<'PY'
import sys
e = bytearray(open(sys.argv[1], 'rb').read()[:128])
w, h, wm, hm = 3840, 2160, 344, 193
e[56] = w & 0xff; e[58] = (e[58] & 0x0f) | ((w >> 8) << 4)
e[59] = h & 0xff; e[61] = (e[61] & 0x0f) | ((h >> 8) << 4)
e[66] = wm & 0xff; e[67] = hm & 0xff; e[68] = ((wm >> 8) << 4) | (hm >> 8)
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], 'wb').write(bytes(e))
PY
check 'UHD laptop saved at 3840x2160: 46 px font' "$(mkroot eDP-1 /tmp/uhd-panel.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=eDP-1\n')" '' \
	'3840x2160,1920x1080,1280x720,1024x768,auto' keep "$CMD" 'sparky-46.pf2'
check 'UHD laptop saved at 1920x1080: 24 px font' "$(mkroot eDP-1 /tmp/uhd-panel.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\nSPARKY_STEREO_CONNECTOR=eDP-1\n')" '' \
	'1920x1080,1280x720,1024x768,auto' keep "$CMD" 'sparky-24.pf2'
echo "SUMMARY $pass of $total pass"
[ "$pass" = "$total" ]
