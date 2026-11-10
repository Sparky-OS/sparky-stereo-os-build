#!/bin/bash
# ORDER 458 proofs, inside a clean amd64 forky container that run.sh started (the published tree r1107a at /repo, deb-multimedia over
# https, the new package at /new). Usage: inside.sh red|green|manual|needed|fresh
#   red      the published 20261106.1 again as the "new" package: the removal must not happen, every end check fails (exit 1)
#   green    the new package over it: apt installed libmlt7-data by itself (automatic), nothing needs it: removed, ours owns the files again
#   manual   libmlt7-data installed by hand (the person asked for it): left and told, then the person lets apt decide (apt-mark auto): removed
#   needed   automatic, but a package that stays needs it: left and told
#   fresh    no shadowing package installed: the pins alone, which names apt will not choose
# The last pipeline's status is never the verdict: every check counts in FAIL and the exit status is FAIL != 0.
set -u
MODE=$1
FAIL=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
eq() { if [ "$2" = "$3" ]; then ok "$1 [$2]"; else bad "$1: got [$2], expected [$3]"; fi; }
check() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
. /t/setup.sh || { echo "rig setup failed"; exit 2; }
SHADOW="libmlt7-data libmlt-7-7 libmlt++-7-7 libmlt7-dev libmlt++7-dev melt7 python3-mlt7 libavcodec-6-dev libavdevice-6-dev libavfilter-6-dev libavformat-6-dev libavutil-6-dev libswresample-6-dev libswscale-6-dev"
case $MODE in
red) NEWDEB=$OLDDEB ;;
*) NEWDEB=$(ls /new/sparky-stereo-apt_*_all.deb | grep -v -- '-lc-hr') ;;
esac
export LC_ALL=C.UTF-8
queries() { for q in producer=avformat consumer=avformat filter=stereo3d_unpack filter=avcolour_space transition=mix; do melt -query $q 2>&1; done | md5sum | cut -c1-32; }
# the 3D path the way Kdenlive reaches it: a side by side frame (left half red, right half blue) through the stereo3d_unpack filter of our MLT
unpack() {
	{ printf 'P6\n64 16\n255\n'; for r in $(seq 16); do for c in $(seq 32); do printf '\377\000\000'; done; for c in $(seq 32); do printf '\000\000\377'; done; done; } >/tmp/sbs.ppm
	tail -c 3072 /tmp/sbs.ppm >/tmp/sbs.rgb
	local o
	for o in left right side_by_side; do
		rm -f /tmp/y.raw
		xvfb-run -a melt avformat:/tmp/sbs.ppm out=0 -filter stereo3d_unpack packing=side_by_side output=$o -consumer avformat:/tmp/y.raw f=rawvideo vcodec=rawvideo pix_fmt=rgb24 >/tmp/melt.log 2>&1
		# one view is 32x16: the first 1536 bytes of the frame (the consumer's buffer is the profile's 64x16, which nothing here scales)
		case $o in
		left) perl -e 'print "\xff\x00\x00" x 512' >/tmp/want.rgb ;;
		right) perl -e 'print "\x00\x00\xff" x 512' >/tmp/want.rgb ;;
		side_by_side) cp /tmp/sbs.rgb /tmp/want.rgb ;;
		esac
		cmp -s -n "$(stat -c %s /tmp/want.rgb)" /tmp/y.raw /tmp/want.rgb || { echo "$o:bad"; return 1; }
	done
	echo ok
}
echo "== $MODE: the pins of today (sparky-stereo-apt $(dpkg-query -W -f='${Version}' sparky-stereo-apt)); the new package is $(basename "$NEWDEB")"
for p in libmlt7-data libmlt-7-7 melt7 libavcodec-6-dev; do echo "today: $(apt-cache policy $p | sed -n 2,3p | tr -s ' ' | tr '\n' ' ')"; done
if [ "$MODE" != fresh ]; then
	apt-get install -y -q melt libmlt-data dpkg-stereo xvfb xauth perl >/tmp/stack.log 2>&1 || { tail /tmp/stack.log; exit 2; }
	BASE=$(queries)
	echo "today (the pins of 20261106.1): apt-get -s install shotcut takes ours out: $(apt-get -s install shotcut 2>&1 | grep -E '^(Inst|Remv)' | grep -E 'shotcut|mlt|melt' | awk '{print $1" "$2}' | tr '\n' ',')"
	eq "ours alone: dpkg-stereo --verify libmlt-data" "$(dpkg-stereo --verify libmlt-data 2>&1 | tail -1 | grep -o '[0-9]* problems')" "0 problems"
	eq "ours alone: the 3D path (stereo3d_unpack: left view red, right view blue, side by side as it came)" "$(unpack)" ok
	echo "melt -query digest before the shadow: $BASE"
	# the state of the A10 and the station: deb-multimedia's package beside ours
	apt-get install -y -q libmlt7-data >/tmp/shadow.log 2>&1
	grep -E 'Replacing files in old package|Setting up libmlt7-data' /tmp/shadow.log
	check "today: libmlt7-data is installed beside libmlt-data" test "$(dpkg-query -W -f='${db:Status-Status}' libmlt7-data)" = installed
	eq "today: dpkg -S /usr/share/mlt-7 names both packages" "$(dpkg -S /usr/share/mlt-7 | sed 's/: .*//' | tr -d ' ' | tr ',' '\n' | sort | tr '\n' ' ')" "libmlt-data libmlt7-data "
	eq "today: dpkg-stereo --verify libmlt-data" "$(dpkg-stereo --verify libmlt-data 2>&1 | tail -1 | grep -o '[0-9]* problems')" "16 problems"
	SHADOWED=$(queries)
	check "today: melt reads another metadata than ours" test "$SHADOWED" != "$BASE"
	echo "melt -query digest with deb-multimedia's data: $SHADOWED"
	eq "today: the 3D path still runs (stereo3d_unpack's own file is ours alone)" "$(unpack)" ok
	case $MODE in
	red | green | needed) apt-mark auto libmlt7-data >/dev/null ;;
	esac
	if [ "$MODE" = needed ]; then
		mkdir -p /tmp/needs/DEBIAN
		printf 'Package: needs-libmlt7-data\nVersion: 1\nArchitecture: all\nMaintainer: t <t@example.org>\nDepends: libmlt7-data\nDescription: a program that needs it\n' >/tmp/needs/DEBIAN/control
		dpkg-deb --root-owner-group -b /tmp/needs /tmp/needs-libmlt7-data_1_all.deb >/dev/null
		apt-get install -y -q /tmp/needs-libmlt7-data_1_all.deb >/dev/null 2>&1
		apt-mark auto libmlt7-data >/dev/null
	fi
	echo "libmlt7-data is $(apt-mark showauto libmlt7-data | grep -q . && echo automatic || echo manual) (apt-mark)"
	echo "== the upgrade to the new package, with no question"
	apt-get install -y "$NEWDEB" >/tmp/new-install.log 2>&1
	eq "the upgrade exits" "$?" 0
	grep -E 'sparky-stereo-apt:' /tmp/new-install.log
	check "the hook told that it settles it after the apt run" grep -q "sparky-stereo-apt: libmlt7-data from deb-multimedia ships files of the edition's packages under another name" /tmp/new-install.log
	UNIT=sparky-stereo-apt-shadowed.service
	# the unit's turn: SYSTEMD=1 (run-systemd.sh: PID 1 is systemd) waits for the unit the hook started and reads its journal; without it (run.sh,
	# no systemd in the container) the unit's command runs by hand, which is all ORDER 458 could prove
	settle() {
		if [ -n "${SYSTEMD:-}" ]; then
			local i st
			# --no-block queued it during apt's run: wait for it to start and end (it waits for apt's locks first)
			for i in $(seq 300); do
				st=$(systemctl show -p ActiveState --value $UNIT)
				{ [ "$st" = inactive ] || [ "$st" = failed ]; } && journalctl -u $UNIT -o cat --no-pager | grep -q . && break
				sleep 1
			done
			echo "unit: ActiveState=$st Result=$(systemctl show -p Result --value $UNIT) ExecMainStatus=$(systemctl show -p ExecMainStatus --value $UNIT) (waited ${i}s)"
			journalctl -u $UNIT -o short-precise --no-pager | grep -v 'apt-get\|Reading\|Building\|Solving' | cut -c1-260
			journalctl -u $UNIT -o cat --no-pager >"$1"
		else
			if [ -x /usr/lib/sparky-stereo-apt/shadowed-by-dmo ]; then /usr/lib/sparky-stereo-apt/shadowed-by-dmo auto 2>&1 | tee "$1"; else echo "no /usr/lib/sparky-stereo-apt/shadowed-by-dmo in this version" | tee "$1"; fi
		fi
	}
	if [ -n "${SYSTEMD:-}" ]; then echo "== settling it: sparky-stereo-apt-shadowed.service under systemd $(systemctl --version | head -1), started by the hook with --no-block"; else echo "== settling it (what sparky-stereo-apt-shadowed.service runs once apt has ended; no systemd in the container)"; fi
	settle /tmp/auto.log
	here() { [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = installed ]; }
	case $MODE in
	red | green)
		if here libmlt7-data; then bad "libmlt7-data is still installed"; else ok "libmlt7-data is gone"; fi
		eq "dpkg -S /usr/share/mlt-7 names" "$(dpkg -S /usr/share/mlt-7 2>&1 | sed 's/: .*//')" "libmlt-data"
		eq "dpkg-stereo --verify libmlt-data" "$(dpkg-stereo --verify libmlt-data 2>&1 | tail -1 | grep -o '[0-9]* problems')" "0 problems"
		eq "melt -query digest is the one before the shadow" "$(queries)" "$BASE"
		eq "the 3D path runs" "$(unpack)" ok
		check "the journal line says what was removed and that ours was installed again" grep -q "libmlt7-data from deb-multimedia ships files of the edition's libmlt-data under another name.*it was removed and libmlt-data was installed again, once" /tmp/auto.log
		check "libmlt-data is still installed at 7.40.0-1+stereo3d5+lc1" test "$(dpkg-query -W -f='${Version}' libmlt-data)" = 7.40.0-1+stereo3d5+lc1
		check "no problem is left in the engine" test -z "$(sparky-stereo-problems list 2>&1 | grep -c shadow | grep -v '^0$')"
		;;
	manual)
		here libmlt7-data && ok "the hand-installed libmlt7-data is left" || bad "the hand-installed libmlt7-data was removed"
		check "it is still manual" test -z "$(apt-mark showauto libmlt7-data)"
		check "the engine keeps a problem that says so" sh -c 'sparky-stereo-problems list 2>&1 | grep -q "You installed it yourself"'
		sparky-stereo-problems list 2>&1 | grep -i -A3 'installed it yourself' | head -5
		echo "== the person lets apt decide (apt-mark auto): the next run settles it"
		apt-mark auto libmlt7-data >/dev/null
		if [ -n "${SYSTEMD:-}" ]; then systemctl start $UNIT; journalctl -u $UNIT -o cat --no-pager >/tmp/auto2.log; else /usr/lib/sparky-stereo-apt/shadowed-by-dmo auto 2>&1 | tee /tmp/auto2.log; fi
		here libmlt7-data && bad "libmlt7-data stays after apt-mark auto" || ok "libmlt7-data is gone after apt-mark auto"
		eq "dpkg-stereo --verify libmlt-data" "$(dpkg-stereo --verify libmlt-data 2>&1 | tail -1 | grep -o '[0-9]* problems')" "0 problems"
		eq "the engine's problem ended with it" "$(sparky-stereo-problems list 2>&1 | grep -c 'You installed it yourself')" 0
		;;
	needed)
		here libmlt7-data && ok "libmlt7-data is left: a package that stays needs it" || bad "libmlt7-data was removed with its dependent"
		here needs-libmlt7-data && ok "the package that needs it stays" || bad "needs-libmlt7-data was removed"
		check "the engine keeps a problem that names the package that needs it" sh -c 'sparky-stereo-problems list 2>&1 | grep -q "it is needed by needs-libmlt7-data"'
		;;
	esac
	echo "== apt's own proposals now (Inst and Remv lines of a simulated dist-upgrade)"
	apt-get -s dist-upgrade 2>&1 | grep -E '^(Inst|Remv)' | grep -E "$(echo $SHADOW | tr ' ' '|')|libmlt|melt" || echo "(none of the shadowing names, none of ours)"
fi
[ "$MODE" = fresh ] && apt-get install -y -q "$NEWDEB" >/tmp/new-install.log 2>&1
echo "== what apt will choose (sparky-stereo-apt $(dpkg-query -W -f='${Version}' sparky-stereo-apt 2>/dev/null))"
for p in $SHADOW; do
	c=$(apt-cache policy "$p" | awk '/Candidate:/ {print $2}')
	if [ "$MODE" = red ]; then
		[ "$c" = "(none)" ] && ok "$p has no candidate" || bad "$p has candidate $c"
	else
		[ "$c" = "(none)" ] && ok "$p has no candidate" || bad "$p has candidate $c"
	fi
done
if [ "$MODE" != manual ] && [ "$MODE" != needed ]; then
	apt-get -s install libmlt7-data >/tmp/sim1.log 2>&1; rc=$?
	eq "apt-get install libmlt7-data: exit status" "$rc" 100
	check "apt says why" grep -q 'Package libmlt7-data is not available\|has no installation candidate' /tmp/sim1.log
	sed -n 1,6p /tmp/sim1.log
	apt-get -s install 'libmlt7-data=1:7.42.0-dmo1' >/tmp/sim2.log 2>&1; rc2=$?
	echo "apt-get install libmlt7-data=1:7.42.0-dmo1 (the version named): exit $rc2: $(grep -E '^(E:|Inst)' /tmp/sim2.log | head -2 | tr '\n' ' ')"
	echo "== a program that wants our MLT: Inst lines of simulated installs"
	for t in melt kdenlive libmlt-dev python3-mlt libavcodec-dev; do
		echo "apt-get -s install $t: $(apt-get -s install $t 2>&1 | grep -E '^(Inst|Remv)' | grep -E 'kdenlive|mlt|melt|libav[a-z]*-(6-)?dev' | awk '{print $1" "$2}' | tr '\n' ',')"
	done
	echo "apt-get -s install shotcut (deb-multimedia's build links its own libmlt-7-7): $(apt-get -s install shotcut 2>&1 | grep -E '^(E:|Inst|Remv)' | grep -E 'shotcut|mlt|melt|E:' | awk '{print $1" "$2" "$3}' | tr '\n' ',')"
	check "apt-get -s install shotcut takes Debian's build and removes nothing of ours" sh -c "apt-get -s install shotcut 2>&1 | grep -q '^Inst shotcut (26.9.27+ds-1 Debian' && ! apt-get -s install shotcut 2>&1 | grep -q '^Remv'"
fi
if [ "$MODE" = fresh ]; then
	dpkg --add-architecture i386; apt-get -qq update >/dev/null 2>&1
	for p in libmlt-7-7:i386 libmlt7-data libavcodec-6-dev:i386 melt7:i386; do echo "i386 view: $p candidate $(apt-cache policy $p | awk '/Candidate:/ {print $2}')"; done
	eq "libavcodec-6-dev:i386 has no candidate" "$(apt-cache policy libavcodec-6-dev:i386 | awk '/Candidate:/ {print $2}')" "(none)"
	echo "Debian has none of these names: $(apt-cache policy $SHADOW | grep -c 'deb.debian.org')"
fi
echo "FAIL count: $FAIL"
exit $((FAIL != 0))
