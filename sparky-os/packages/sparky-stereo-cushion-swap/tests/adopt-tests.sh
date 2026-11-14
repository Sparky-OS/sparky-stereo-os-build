#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
# Tests of cushion-swap --adopt (0.3.5, ORDER 572) on fstab fixtures, as an ordinary user in a container:
# the installer's line is taken, a hand-made line is left on an upgrade, the person's word takes it, an area that is
# already named is untouched, and the daemon then finds the area.
#   adopt-tests.sh [CUSHION_SWAP]     the program under test (default: ../sbin/cushion-swap)
set -u
HERE=$(cd "$(dirname "$0")" && pwd); PKG=$(dirname "$HERE")
BIN=${1:-$PKG/sbin/cushion-swap}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
pass=0; total=0
U=48b761e1-0141-4e6d-bb60-ebc03fb81fd1
# what Calamares' fstab step prints: "{:41} {:<14} {:<7} {:<10} 0 {}"
installer_line() { printf '%-41s %-14s %-7s %-10s 0 %s\n' "$1" "$2" "$3" "$4" "$5"; }
fixture() {   # fixture NAME SWAPLINE...
	mkdir -p "$W/$1/default" "$W/$1/var"
	{ echo '# /etc/fstab: static file system information.'; installer_line UUID=a124cd50-863b-4587-a0c2-58a539a01eb7 / ext4 defaults 1
	  shift; printf '%s\n' "$@"; installer_line UUID=D5EE-21BB /boot/efi vfat umask=0077 2; } > "$W/${1}/fstab"
}
run() {       # run NAME MODE [AREA]
	env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 FSTAB_PATH="$W/$1/fstab" CALIBRATION_DIR="$W/$1/var" CUSHION_SWAP_AREA="${3:-}" \
		CUSHION_SWAP_LANG_DIR="$PKG/lang" CUSHION_SWAP_CONFIG="$W/$1/default/none" bash "$BIN" --adopt "$2" > "$W/$1/out" 2>&1
	echo $? > "$W/$1/rc"
}
check() {     # check NAME TEST...
	total=$((total + 1)); local name=$1; shift
	if "$@"; then pass=$((pass + 1)); echo "PASS  $name"; else echo "FAIL  $name"; fi
}
swapline() { awk '$3 == "swap"' "$W/$1/fstab"; }

fixture inst "$(installer_line UUID=$U swap swap defaults 0)"; cp "$W/inst/fstab" "$W/inst/before"; run inst installer
check 'installer: the line is marked noauto, in the installer own columns' [ "$(swapline inst)" = "$(installer_line UUID=$U swap swap noauto 0)" ]
check 'installer: nothing else in the file changed' [ "$(grep -v ' swap ' "$W/inst/fstab")" = "$(grep -v ' swap ' "$W/inst/before")" ]
check 'installer: the file as it was is kept' cmp -s "$W/inst/before" "$W/inst/fstab.before-cushion-swap"
check 'installer: said' grep -q "takes the swap area the installer made (UUID=$U)" "$W/inst/out"
check 'installer: recorded' grep -q " installer UUID=$U\$" "$W/inst/var/adopted"
check 'installer: exit 0' [ "$(cat "$W/inst/rc")" = 0 ]
run inst installer
check 'a second run changes nothing' [ "$(swapline inst)" = "$(installer_line UUID=$U swap swap noauto 0)" ]
check 'a second run records nothing more' [ "$(wc -l < "$W/inst/var/adopted")" = 1 ]

fixture up "$(installer_line UUID=$U swap swap defaults 0)"; run up upgrade
check 'upgrade: the installer own line is taken' [ "$(swapline up)" = "$(installer_line UUID=$U swap swap noauto 0)" ]
fixture hand "UUID=$U none swap sw 0 0"; cp "$W/hand/fstab" "$W/hand/before"; run hand upgrade
check 'upgrade: a line written by hand is left as it is' cmp -s "$W/hand/before" "$W/hand/fstab"
check 'upgrade: and that is said, with the command' grep -q "is not the installer's own.*cushion-swap --adopt mine" "$W/hand/out"
fixture edited "UUID=$U swap swap defaults,pri=5 0 0"; cp "$W/edited/fstab" "$W/edited/before"; run edited upgrade
check 'upgrade: the installer line with an option the person added is left' cmp -s "$W/edited/before" "$W/edited/fstab"
fixture file "$(installer_line /swapfile swap swap defaults 0)"; run file upgrade
check 'upgrade: the installer swap file line is taken' [ "$(swapline file)" = "$(installer_line /swapfile swap swap noauto 0)" ]
run hand mine
check 'mine: the person word takes the hand-made line' [ "$(swapline hand | awk '{print $4}')" = noauto ]
fixture named "$(installer_line UUID=$U swap swap defaults 0)"; cp "$W/named/fstab" "$W/named/before"; run named upgrade /swapfile
check 'AREA= is set: nothing is touched' cmp -s "$W/named/before" "$W/named/fstab"
fixture auto "$(installer_line UUID=$U swap swap noauto 0)"; cp "$W/auto/fstab" "$W/auto/before"; run auto installer
check 'a noauto line exists: nothing is touched' cmp -s "$W/auto/before" "$W/auto/fstab"
fixture none; cp "$W/none/fstab" "$W/none/before"; run none installer
check 'no swap line: nothing is touched, exit 0' [ "$(cat "$W/none/rc")" = 0 ]
fixture zr "/dev/zram0 none swap defaults 0 0"; cp "$W/zr/fstab" "$W/zr/before"; run zr mine
check 'a zram line is never taken' cmp -s "$W/zr/before" "$W/zr/fstab"
run inst bogus
check 'an unknown mode is refused' [ "$(cat "$W/inst/rc")" = 2 ]
echo "SUMMARY $pass of $total pass"
[ "$pass" = "$total" ]
