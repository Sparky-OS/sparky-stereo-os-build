#!/bin/sh
# The KDE splash is ours by default, and the person's own choice stays (ORDER 472).
# Runs where libkf6config-bin is installed (kreadconfig6), in a container: KConfig reads /etc/xdg/ksplashrc below
# the person's ~/.config/ksplashrc, key by key, exactly as startplasma reads [KSplash] Theme (default Breeze).
# usage: ksplashrc.sh XDG_FILE    (the package's default/xdg/ksplashrc; "none" for the control without it)
set -eu
export LC_ALL=C.UTF-8
SRC=${1:?usage: ksplashrc.sh XDG_FILE|none}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/etc/xdg"
[ "$SRC" = none ] || cp "$SRC" "$W/etc/xdg/ksplashrc"
fail=0
check() {   # check NAME EXPECTED_THEME  (the person's home is $W/home)
	got=$(HOME=$W/home XDG_CONFIG_HOME=$W/home/.config XDG_CONFIG_DIRS=$W/etc/xdg kreadconfig6 --file ksplashrc --group KSplash --key Theme --default Breeze)
	eng=$(HOME=$W/home XDG_CONFIG_HOME=$W/home/.config XDG_CONFIG_DIRS=$W/etc/xdg kreadconfig6 --file ksplashrc --group KSplash --key Engine --default KSplashQML)
	if [ "$got" = "$2" ] && [ "$eng" = KSplashQML ]; then
		echo "ok   $1: $got"
	else
		echo "FAIL $1: Theme=$got Engine=$eng, wanted $2"; fail=$((fail + 1))
	fi
}
person() { rm -rf "$W/home"; mkdir -p "$W/home/.config"; [ -z "${1:-}" ] || printf '%s' "$1" > "$W/home/.config/ksplashrc"; }
OURS=org.sparkystereo.desktop
person;                                                        check 'new user, no file' $OURS
person '';                                                     check 'empty file' $OURS
person '[General]
Foo=bar
';                                                             check 'file with other groups only' $OURS
person '[KSplash]
Engine=KSplashQML
';                                                             check 'KSplash group without Theme' $OURS
person '[KSplash]
Engine=KSplashQML
Theme=org.kde.breeze.desktop
';                                                             check "person's own splash" org.kde.breeze.desktop
person '[KSplash]
Engine=KSplashQML
Theme=None
';                                                             check "person's None" None
echo "$fail failing"
[ "$fail" = 0 ]
