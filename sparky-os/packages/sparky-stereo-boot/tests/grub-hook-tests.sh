#!/bin/bash
# Tests of 30-sparky-stereo-boot.cfg: sourced the way grub-mkconfig sources /etc/default/grub.d,
# in a fake root, and the GRUB_* values it leaves compared with what each case must give; from 0.1.5 also
# what it says on update-grub's output, the problems it keeps (lib/problems.py) and the record of what GRUB
# was given (/var/lib/sparky-stereo-boot/grub-display).
#   grub-hook-tests.sh HOOK FIXTURES
HOOK=$(readlink -f "$1"); FIX=$(readlink -f "$2")
PKG=$(dirname "$(dirname "$HOOK")")
# the problems are kept by the engine (sparky-stereo-problems, 0.1.6), its messages from catalogs of the package's lang/
CAT=$(mktemp -d); sparky-stereo-problems catalog sparky-stereo-boot "$PKG/lang" "$CAT" --subject LOCAL19 >/dev/null
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
	out=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$2" SPARKY_FONT_DIR="$2/fonts" \
		SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 bash -c "
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
# 0.1.5: told, kept and recorded. told NAME ROOT PRESET PATH-FIRST WANT-VARS STDERR-PATTERN KEPT DECISION
#   KEPT is STEP:KEY, or -STEP for none; DECISION a pattern grub-display must match
told() {
	total=$((total + 1))
	R=$2
	out=$(env -i PATH="${4:+$4:}/usr/sbin:/usr/bin:/sbin:/bin" SPARKY_STEREO_ROOT="$R" SPARKY_FONT_DIR="$R/fonts" \
		SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 bash -c "
		GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'; $3
		. '$HOOK'
		printf '%s|%s' \"\$GRUB_GFXMODE\" \"\${GRUB_FONT##*/}\"" 2> "$R/stderr")
	step=${7#-}; step=${step%%:*}
	kept=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["message"])' "$R/var/lib/sparky-stereo-problems/sparky-stereo-boot_$step.json" 2>/dev/null || echo none)
	case $7 in -*) want_kept=none ;; *) want_kept=${7#*:} ;; esac
	said=$(grep -c -E "$6" "$R/stderr")
	decided=$(grep -c -E "$8" "$R/var/lib/sparky-stereo-boot/grub-display" 2>/dev/null)
	if [ "$out" = "$5" ] && [ "$said" -ge 1 ] && [ "$kept" = "$want_kept" ] && [ "${decided:-0}" -ge 1 ]; then
		pass=$((pass + 1)); echo "PASS  $1: $out; said; kept $kept; recorded"
	else
		echo "FAIL  $1: got [$out] want [$5]; said $said ($6); kept [$kept] want [$want_kept]; recorded ${decided:-0} ($8)"
		sed 's/^/      stderr: /' "$R/stderr"
	fi
}
told 'saved mode: the resolution list is said and recorded' "$(mkroot HDMI-A-1 $FIX/hx855.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\nSPARKY_STEREO_CONNECTOR=HDMI-A-1\n')" '' '' \
	'1920x1080,1280x720,1024x768,auto|' "GRUB's resolution: 1920x1080; when the firmware does not offer it, the first it offers of 1280x720, 1024x768, else its own" \
	-grub-display 'WANTED=1920x1080'
R=$(mkroot HDMI-A-1 $FIX/hx855.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\n'); echo disconnected > "$R/sys/class/drm/card0-HDMI-A-1/status"
told 'no connected screen, saved mode: said and kept, saved resolution, GRUB font' "$R" '' '' \
	'1920x1080,1280x720,1024x768,auto|' 'no connected screen reported its size \(EDID\), so GRUB.s menu uses 1920x1080 and GRUB.s own font' \
	grub-display:LOCAL41 'SOURCE=saved'
R=$(mkroot HDMI-A-1 $FIX/hx855.edid); echo disconnected > "$R/sys/class/drm/card0-HDMI-A-1/status"
told 'no connected screen, nothing saved: the firmware resolution, said and kept' "$R" '' '' \
	'|' "GRUB's menu uses the firmware's resolution and GRUB's own font" grub-display:LOCAL41 'WANTED=auto'
mkdir -p /tmp/grub-hook-fake-$$; printf '#!/bin/sh\necho "grub-mkfont: error: fake failure for the test" >&2\nexit 1\n' > /tmp/grub-hook-fake-$$/grub-mkfont; chmod 755 /tmp/grub-hook-fake-$$/grub-mkfont
told 'grub-mkfont fails: said with its error, kept, GRUB font' "$(mkroot eDP-1 /tmp/uhd-panel.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=eDP-1\n')" '' /tmp/grub-hook-fake-$$ \
	'3840x2160,1920x1080,1280x720,1024x768,auto|' "GRUB's menu font of 46 pixels could not be made: grub-mkfont: error: fake failure for the test" grub-font:LOCAL44 'FONT=$'
told 'the font named in GRUB_STEREO_FONT cannot be read: said and kept' "$(mkroot eDP-1 /tmp/uhd-panel.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=eDP-1\n')" 'GRUB_STEREO_FONT=/nonexistent/font.ttf' '' \
	'3840x2160,1920x1080,1280x720,1024x768,auto|' 'font of 46 pixels could not be made: /nonexistent/font.ttf: cannot be read' grub-font:LOCAL44 'SOURCE=saved'
R=$(mkroot eDP-1 /tmp/uhd-panel.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=eDP-1\n')
SPARKY_STEREO_ROOT="$R" SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" sparky-stereo-problems keep --machine --quiet sparky-stereo-boot grub-font LOCAL44 46 old
told 'the font is made again: the kept problem is cleared, the font recorded' "$R" '' '' \
	'3840x2160,1920x1080,1280x720,1024x768,auto|sparky-46.pf2' "GRUB's resolution: 3840x2160" -grub-font 'FONT=.*sparky-46.pf2'
python3 - "$FIX/hx855.edid" /tmp/nosize.edid <<'PY2'
import sys
e = bytearray(open(sys.argv[1], 'rb').read()[:128])
e[66] = e[67] = e[68] = 0
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], 'wb').write(bytes(e))
PY2
told 'a projector with no physical size: said, not kept (nothing to repair)' "$(mkroot HDMI-A-1 /tmp/nosize.edid)" '' '' \
	'1920x1080,1280x720,1024x768,auto|' 'the screen card0-HDMI-A-1 gave no physical size in its EDID' -grub-display 'SOURCE=native'
rm -rf /tmp/grub-hook-fake-$$ /tmp/nosize.edid
echo "SUMMARY $pass of $total pass"
[ "$pass" = "$total" ]
