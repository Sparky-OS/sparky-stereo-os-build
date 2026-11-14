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
e[21] = round(wm / 10); e[22] = round(hm / 10)   # the screen size field, centimetres (E-EDID 3.6.2)
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], 'wb').write(bytes(e))
PY
check 'UHD laptop saved at 3840x2160: 46 px font' "$(mkroot eDP-1 /tmp/uhd-panel.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=eDP-1\n')" '' \
	'3840x2160,1920x1080,1280x720,1024x768,auto' keep "$CMD" 'sparky-46.pf2'
check 'UHD laptop saved at 1920x1080: 24 px font' "$(mkroot eDP-1 /tmp/uhd-panel.edid '' 'SPARKY_STEREO_GFXMODE=1920x1080\nSPARKY_STEREO_CONNECTOR=eDP-1\n')" '' \
	'1920x1080,1280x720,1024x768,auto' keep "$CMD" 'sparky-24.pf2'
# 0.1.7: one text height for every screen, at a desk (Daniel, 2026-11-02: "I sit at 50cm from the screen, I use it as
# a monitor, and people installing sparky will be installing on a PC, not in a television"). A 43 inch UHD screen
# (941 x 529 mm) reports a television's size: 4.2 mm is 17 px there, GRUB's own font (0.1.6 made it 38 px, for 1.3 m);
# a 27 inch UHD monitor (597 x 336 mm) keeps 28 px; the person's GRUB_STEREO_TEXT_MM and GRUB_FONT still decide.
edid() {     # edid FILE WIDTH HEIGHT WIDTH_MM HEIGHT_MM
	python3 - "$FIX/hx855.edid" "$@" <<'PY'
import sys
e = bytearray(open(sys.argv[1], 'rb').read()[:128])
w, h, wm, hm = (int(v) for v in sys.argv[3:7])
e[56] = w & 0xff; e[58] = (e[58] & 0x0f) | ((w >> 8) << 4)
e[59] = h & 0xff; e[61] = (e[61] & 0x0f) | ((h >> 8) << 4)
e[66] = wm & 0xff; e[67] = hm & 0xff; e[68] = ((wm >> 8) << 4) | (hm >> 8)
e[21] = round(wm / 10); e[22] = round(hm / 10)   # the screen size field, centimetres (E-EDID 3.6.2)
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], 'wb').write(bytes(e))
PY
}
edid /tmp/uhd-43.edid 3840 2160 941 529
edid /tmp/uhd-27.edid 3840 2160 597 336
check '43 inch UHD screen: the desk size, GRUB font (no television scaling)' "$(mkroot HDMI-A-1 /tmp/uhd-43.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=HDMI-A-1\n')" '' \
	'3840x2160,1920x1080,1280x720,1024x768,auto' keep "$CMD" ''
check '27 inch UHD monitor: 28 px font' "$(mkroot DP-1 /tmp/uhd-27.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=DP-1\n')" '' \
	'3840x2160,1920x1080,1280x720,1024x768,auto' keep "$CMD" 'sparky-28.pf2'
check 'GRUB_STEREO_TEXT_MM=9 on the 43 inch screen: 36 px font' "$(mkroot HDMI-A-1 /tmp/uhd-43.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=HDMI-A-1\n')" 'GRUB_STEREO_TEXT_MM=9' \
	'3840x2160,1920x1080,1280x720,1024x768,auto' keep "$CMD" 'sparky-36.pf2'
check 'GRUB_FONT set by the person on the 43 inch screen: kept' "$(mkroot HDMI-A-1 /tmp/uhd-43.edid '' 'SPARKY_STEREO_GFXMODE=3840x2160\nSPARKY_STEREO_CONNECTOR=HDMI-A-1\n')" 'GRUB_FONT=/boot/grub/fonts/mine.pf2' \
	'3840x2160,1920x1080,1280x720,1024x768,auto' keep "$CMD" 'mine.pf2'
rm -f /tmp/uhd-43.edid /tmp/uhd-27.edid
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
e[21] = e[22] = 0   # a projector: the screen size field undefined too (E-EDID 3.6.2)
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], 'wb').write(bytes(e))
PY2
told 'a projector with no physical size: said, not kept (nothing to repair)' "$(mkroot HDMI-A-1 /tmp/nosize.edid)" '' '' \
	'1920x1080,1280x720,1024x768,auto|' 'the screen card0-HDMI-A-1 gave no physical size in its EDID' -grub-display 'SOURCE=native'
# 0.1.10 (ORDER 572): the screen's size from both EDID fields. A 13.3 inch full HD panel whose screen size field says
# 29 x 17 cm (right) and whose first timing says 344 x 193 mm (a 15.5 inch panel): the screen size field decides
# (VESA E-EDID 3.6.2: "The host (source) is expected to use this data to get a rough idea of the image size to generate
# properly scaled text and icons"), 4.2 mm is 28 px there (the timing's size gave 24), and update-grub says so.
sizes() {    # sizes FILE WIDTH HEIGHT SCREEN_CM_W SCREEN_CM_H TIMING_MM_W TIMING_MM_H
	python3 - "$FIX/hx855.edid" "$@" <<'PY3'
import sys
e = bytearray(open(sys.argv[1], 'rb').read()[:128])
w, h, cw, ch, wm, hm = (int(v) for v in sys.argv[3:9])
e[56] = w & 0xff; e[58] = (e[58] & 0x0f) | ((w >> 8) << 4)
e[59] = h & 0xff; e[61] = (e[61] & 0x0f) | ((h >> 8) << 4)
e[21] = cw; e[22] = ch
e[66] = wm & 0xff; e[67] = hm & 0xff; e[68] = ((wm >> 8) << 4) | (hm >> 8)
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], 'wb').write(bytes(e))
PY3
}
sizes /tmp/two-sizes.edid 1920 1080 29 17 344 193
sizes /tmp/screen-only.edid 1920 1080 29 17 0 0
sizes /tmp/agree.edid 1920 1080 29 17 294 165
sizes /tmp/desk-24.edid 1920 1080 53 30 531 299
told 'two sizes in the EDID: the screen size field decides, 28 px, said' "$(mkroot eDP-1 /tmp/two-sizes.edid)" '' '' \
	'1920x1080,1280x720,1024x768,auto|sparky-28.pf2' 'gives two sizes in its EDID: 290 x 170 mm as the screen.s size and 344 x 193 mm for its first timing' -grub-display 'TEXT=sized'
told 'only the screen size field: 28 px' "$(mkroot eDP-1 /tmp/screen-only.edid)" '' '' \
	'1920x1080,1280x720,1024x768,auto|sparky-28.pf2' "GRUB's resolution: 1920x1080" -grub-display 'FONT=.*sparky-28.pf2'
total=$((total + 1)); R=$(mkroot eDP-1 /tmp/agree.edid)
if env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$R" SPARKY_FONT_DIR="$R/fonts" SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" \
	SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 bash -c ". '$HOOK'" 2>&1 | grep -q 'two sizes'; then
	echo 'FAIL  the two fields agree (294 x 165 mm, 29 x 17 cm): nothing to say'
else pass=$((pass + 1)); echo 'PASS  the two fields agree (294 x 165 mm, 29 x 17 cm): nothing said about two sizes'; fi
rm -rf "$R"
# Secure Boot: no font file is named (Debian's signed GRUB refuses it: grub-core/kern/efi/sb.c, "prohibited by secure
# boot policy"); on a dense panel the menu is given the resolutions at which GRUB's own 16 px font has the text height
sb() { mkdir -p "$1/sys/firmware/efi/efivars"; printf '\006\000\000\000\00'"$2" > "$1/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"; echo "$1"; }
told 'Secure Boot on, dense panel: no font file, the readable resolutions, said' "$(sb "$(mkroot eDP-1 /tmp/two-sizes.edid)" 1)" '' '' \
	'1280x720,1366x768,1600x900,1024x768,auto|' 'Secure Boot is on: Debian.s signed GRUB loads only the font inside it \(16 pixels\), so GRUB.s menu is shown at 1280x720, where its text is about 3.6 mm high' -grub-display 'SOURCE=readable'
told 'Secure Boot on, recorded' "$(sb "$(mkroot eDP-1 /tmp/two-sizes.edid)" 1)" '' '' \
	'1280x720,1366x768,1600x900,1024x768,auto|' 'SPARKY_STEREO_SECUREBOOT_TEXT=native' -grub-display 'SECUREBOOT=on'
told 'Secure Boot off in the firmware (variable 0): the sized font as before' "$(sb "$(mkroot eDP-1 /tmp/two-sizes.edid)" 0)" '' '' \
	'1920x1080,1280x720,1024x768,auto|sparky-28.pf2' "GRUB's resolution: 1920x1080" -grub-display 'SECUREBOOT=off'
told 'Secure Boot on, SPARKY_STEREO_SECUREBOOT_TEXT=native: the screen resolution, no font file, said' \
	"$(sb "$(mkroot eDP-1 /tmp/two-sizes.edid 'SPARKY_STEREO_SECUREBOOT_TEXT=native\n')" 1)" '' '' \
	'1920x1080,1280x720,1024x768,auto|' 'so GRUB.s menu has small text at 1920x1080 on this screen' -grub-display 'TEXT=grub'
told 'Secure Boot on, a 24 inch full HD monitor: GRUB font at the screen resolution (16 px is the size there)' "$(sb "$(mkroot DP-1 /tmp/desk-24.edid)" 1)" '' '' \
	'1920x1080,1280x720,1024x768,auto|' "GRUB's resolution: 1920x1080" -grub-display 'TEXT=grub'
told 'Secure Boot on, the person set GRUB_GFXMODE: kept, no font file' "$(sb "$(mkroot eDP-1 /tmp/two-sizes.edid)" 1)" 'GRUB_GFXMODE=1920x1080' '' \
	'1920x1080|' 'small text at 1920x1080' -grub-display 'SOURCE=person'
# the menu: hidden with no wait when this is the only system, shown when another is found; the person's settings win
menu() {     # menu NAME ROOT PRESET OS_PROBER_OUTPUT_OR_fail WANT(style|timeout) SAID RECORDED
	total=$((total + 1)); R=$2
	mkdir -p "$R/bin"
	if [ "$4" = fail ]; then printf '#!/bin/sh\nexit 1\n' > "$R/bin/prober"; else printf '#!/bin/sh\nprintf "%%s" "%s"\n' "$4" > "$R/bin/prober"; fi
	chmod 755 "$R/bin/prober"
	out=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$R" SPARKY_FONT_DIR="$R/fonts" SPARKY_OS_PROBER="$R/bin/prober" \
		SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 bash -c "
		GRUB_TIMEOUT=5; $3
		. '$HOOK'
		printf '%s|%s' \"\$GRUB_TIMEOUT_STYLE\" \"\$GRUB_TIMEOUT\"" 2> "$R/stderr")
	said=$(grep -c -E "$6" "$R/stderr"); decided=$(grep -c -E "$7" "$R/var/lib/sparky-stereo-boot/grub-display" 2>/dev/null)
	if [ "$6" = - ]; then said=1; [ -s "$R/stderr" ] && said=0; fi   # -: nothing may be said
	if [ "$out" = "$5" ] && [ "$said" -ge 1 ] && [ "${decided:-0}" -ge 1 ]; then pass=$((pass + 1)); echo "PASS  $1: $out; said; recorded"
	else echo "FAIL  $1: got [$out] want [$5]; said $said ($6); recorded ${decided:-0} ($7)"; sed 's/^/      stderr: /' "$R/stderr"; fi
	rm -rf "$R"
}
WIN='/dev/sda1@/efi/Microsoft/Boot/bootmgfw.efi:Windows Boot Manager:Windows:efi\n'
menu 'the only system (os-prober off, as Debian ships it): hidden, no wait' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" '' "$WIN" \
	'hidden|0' 'menu is hidden and the system starts at once' 'MENU=hidden'
menu 'os-prober on and Windows found: shown, 5 seconds' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" 'GRUB_DISABLE_OS_PROBER=false' "$WIN" \
	'menu|5' 'shown for 5 seconds: another system is on this computer \(Windows Boot Manager\)' 'MENU=shown'
menu 'os-prober on and another Linux found: shown' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" 'GRUB_DISABLE_OS_PROBER=false' '/dev/sda4:Other Linux 1:other:linux\n' \
	'menu|5' 'another system is on this computer \(Other Linux 1\)' 'MENU=shown'
menu 'os-prober on and nothing found (the other system is gone): hidden again' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" 'GRUB_DISABLE_OS_PROBER=false' '' \
	'hidden|0' 'menu is hidden' 'MENU=hidden'
menu 'os-prober fails: shown, and said (never hidden on a guess)' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" 'GRUB_DISABLE_OS_PROBER=false' fail \
	'menu|5' 'os-prober failed, so GRUB.s menu is shown for 5 seconds' 'MENU=shown'
menu 'the person set GRUB_TIMEOUT_STYLE and GRUB_TIMEOUT: kept' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" 'GRUB_TIMEOUT_STYLE=countdown; GRUB_TIMEOUT=3' "$WIN" \
	'countdown|3' 'your own settings are kept \(GRUB_TIMEOUT_STYLE=countdown, GRUB_TIMEOUT=3\)' 'MENU=person'
menu 'the person set GRUB_TIMEOUT=10 alone: kept, shown as GRUB shows it' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" 'GRUB_TIMEOUT=10' '' \
	'|10' 'your own settings are kept' 'MENU=person'
menu 'a hand-made hidden menu (GRUB_TIMEOUT_STYLE=hidden, GRUB_TIMEOUT=0): the same two keys, kept' "$(mkroot HDMI-A-1 $FIX/hx855.edid)" 'GRUB_TIMEOUT_STYLE=hidden; GRUB_TIMEOUT=0' "$WIN" \
	'hidden|0' 'your own settings are kept' 'MENU=person'
menu 'SPARKY_STEREO_MENU=shown: always shown' "$(mkroot HDMI-A-1 $FIX/hx855.edid 'SPARKY_STEREO_MENU=shown\n')" '' '' \
	'menu|5' 'shown for 5 seconds: SPARKY_STEREO_MENU=shown' 'MENU=shown'
menu 'SPARKY_STEREO_BOOT=no: the menu as the system left it' "$(mkroot HDMI-A-1 $FIX/hx855.edid 'SPARKY_STEREO_BOOT=no\n')" '' "$WIN" \
	'|5' - 'SOURCE=off'
# sourced a second time in a process that inherited the first run's exports: still the screen's own values, not "the person's"
total=$((total + 1)); R=$(mkroot eDP-1 /tmp/two-sizes.edid)
out=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$R" SPARKY_FONT_DIR="$R/fonts" SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" \
	SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 bash -c "GRUB_TIMEOUT=5; . '$HOOK'; bash -c \". '$HOOK'\"; grep -E '^(SOURCE|MENU)=' '$R/var/lib/sparky-stereo-boot/grub-display' | tr '\n' ' '" 2>/dev/null)
if [ "$out" = 'SOURCE=native MENU=hidden ' ]; then pass=$((pass + 1)); echo "PASS  sourced again with its own exported values: $out"; else echo "FAIL  sourced again with its own exported values: got [$out] want [SOURCE=native MENU=hidden ]"; fi
rm -rf "$R"
rm -rf /tmp/grub-hook-fake-$$ /tmp/nosize.edid /tmp/two-sizes.edid /tmp/screen-only.edid /tmp/agree.edid /tmp/desk-24.edid
echo "SUMMARY $pass of $total pass"
[ "$pass" = "$total" ]
