#!/bin/bash
# sparky-stereo-console: a person's change to the console's eight files under /etc is kept across upgrades (row 813).
# Root, in a throwaway container of the published edition (the console and its diversions installed), no network.
#   etc-files.sh CASE NEW [FROM]
#     CASE  up-none     upgrade, nothing changed: every file is the new package's, nothing said, nothing asked,
#                       what a login and a new account show is unchanged; then removal and purge
#           up-edited   a person's change planted in each of the eight files before the upgrade: each kept byte
#                       for byte, the new default beside it and said once, nothing asked, each named by
#                       dpkg-stereo --verify (or --verify --deep); then removal and purge
#           fresh       the published console purged first, then the package under test installed
#           say         the sentences in the ten languages
#     NEW   a folder with the package under test and its -lc-hr companion; FROM: a folder installed first
# apt runs carry no --force-conf* and read /dev/null: a dpkg question fails the run. Exit 1 on any FAIL.
set -u
CASE=$1 NEW=$(readlink -f "$2") FROM=${3:-}
PKG=sparky-stereo-console
EIGHT="/etc/issue /etc/issue.net /etc/motd /etc/nanorc /etc/zsh/zshrc /etc/update-motd.d/10-uname /etc/skel/.bash_aliases /etc/skel/.selected_editor"
FIVE="/etc/issue /etc/issue.net /etc/update-motd.d/10-uname /etc/nanorc /etc/zsh/zshrc"
T=/tmp/etc-files; rm -rf $T; mkdir -p $T/ref $T/before
failed=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; failed=1; fi; }
apt_y() { apt-get -y -q -o Dpkg::Use-Pty=0 -o APT::Color=0 "$@" </dev/null; }
sha() { sha256sum <"$1" 2>/dev/null | cut -c1-64; }
asked() { grep -c -E 'Configuration file|end of file on <standard input>|Modified locally|Deleted locally' "$1"; }
dpkg-deb -x "$NEW/${PKG}_"*_all.deb $T/ref
ref() { case $1 in /etc/motd|/etc/skel/*) echo "$T/ref$1" ;; *) echo "$T/ref/usr/share/$PKG/defaults$1" ;; esac; }
view() { # what a login and a new account show: the login texts, the message of the day's script, a new home
	{ for f in /etc/issue /etc/issue.net /etc/motd; do echo "== $f"; cat "$f"; done
	  echo '== 10-uname'; sh /etc/update-motd.d/10-uname | sed 's/ [0-9][^ ]*-[^ ]* / KERNEL /'
	  u=u$RANDOM; useradd -m -s /bin/bash "$u" && { echo "== home"; ls -A "/home/$u"
	  for f in .bash_aliases .selected_editor .bashrc; do echo "== $f"; cat "/home/$u/$f" 2>/dev/null; done; userdel -r "$u" 2>/dev/null; }
	  echo '== nano'; grep -v '^#' /etc/nanorc | grep . | md5sum
	  echo '== zsh'; cat /etc/zsh/zshrc; } >"$1" 2>&1; }
named() { grep -E "^(CHANGED|LCCHANGED|EDITED|AFTERINST|MISSING) +$1( |$)" $T/verify.txt $T/deep.txt >/dev/null; }

if [ "$CASE" = say ]; then
	S=/tmp/say.sh
	dpkg-deb -e "$NEW/${PKG}_"*_all.deb $T/ctl
	{ echo 'package=sparky-stereo-console'; sed -n '/^say_default() {/,/^}/p' $T/ctl/postinst; sed -n '/^say_moved() {/,/^}/p' $T/ctl/postrm; } >$S
	prev=
	for L in en_US pl_PL pt_BR fr_FR de_DE es_ES ja_JP ko_KR zh_CN zh_TW; do
		a=$(LANG=$L.UTF-8 sh -c ". $S; say_default /etc/issue /etc/issue.dpkg-dist" 2>&1)
		b=$(LANG=$L.UTF-8 sh -c ". $S; say_moved /etc/issue /var/backups/$PKG/etc/issue" 2>&1)
		echo "$L: $a | $b"
		check '[ -n "$a" ] && [ "$a" != "$prev" ] && case "$a" in *"/etc/issue"*"/etc/issue.dpkg-dist"*) true ;; *) false ;; esac' "$L: the upgrade sentence names both paths, in its own words"
		check 'case "$b" in *"/etc/issue"*"/var/backups/'$PKG'/etc/issue"*) true ;; *) false ;; esac' "$L: the removal sentence names both paths"
		prev=$a
	done
	exit $failed
fi

if [ "$CASE" = fresh ]; then
	dpkg --purge $PKG $PKG-lc-hr >$T/purge0.log 2>&1
	check '[ -z "$(dpkg-divert --listpackage /etc/issue)" ] && [ -f /etc/issue ]' "the published console purged: base-files' /etc/issue back, no diversion"
	apt_y install "$NEW"/*.deb >$T/install.log 2>&1; rc=$?
	check '[ $rc = 0 ] && [ "$(asked $T/install.log)" = 0 ]' "fresh install: rc $rc, nothing asked"
	for f in $EIGHT; do check '[ "$(sha "$f")" = "$(sha "$(ref "$f")")" ]' "fresh: $f is the package's"; done
	for f in /etc/issue:base-files /etc/issue.net:base-files /etc/update-motd.d/10-uname:base-files /etc/nanorc:nano /etc/zsh/zshrc:zsh-common; do
		p=${f%%:*} o=${f#*:}; h=$(dpkg-query -W -f='${Conffiles}\n' "$o" 2>/dev/null | awk -v p="$p" '$1 == p {print $2}')
		check '[ -n "$h" ] && [ "$h" != newconffile ] && [ "$(md5sum <"$p.debian" | cut -d" " -f1)" = "$h" ]' "fresh: $o's $p kept at $p.debian with its hash ($h)"
	done
	check '! grep -q "Your changes" $T/install.log' "fresh: nothing said"
	exit $failed
fi

[ -n "$FROM" ] && { apt_y install "$FROM"/*.deb >$T/from.log 2>&1 || { echo "FAIL installing FROM"; tail -3 $T/from.log; exit 1; }; }
echo "from: $(dpkg-query -W -f='${Version}' $PKG)"
view $T/view-before.txt
if [ "$CASE" = up-edited ]; then
	for f in $EIGHT; do mkdir -p "${f%/*}"; [ -e "$f" ] || : >"$f"; printf '# a person'"'"'s change to %s\n' "$f" >>"$f"; cp -p "$f" "$T/before/${f//\//_}"; done
fi
apt_y install "$NEW"/*.deb >$T/up.log 2>&1; rc=$?
echo "to: $(dpkg-query -W -f='${Version}' $PKG)"
check '[ $rc = 0 ] && [ "$(asked $T/up.log)" = 0 ]' "upgrade: rc $rc, nothing asked"
check '[ "$(dpkg-query -W -f="\${Status}" $PKG)" = "install ok installed" ] && [ -z "$(dpkg --audit 2>&1)" ]' "upgrade: installed, dpkg --audit empty"
dpkg-stereo --verify >$T/verify.txt 2>&1; vrc=$?
dpkg-stereo --verify --deep >$T/deep.txt 2>&1
if [ "$CASE" = up-none ]; then
	for f in $EIGHT; do check '[ "$(sha "$f")" = "$(sha "$(ref "$f")")" ]' "untouched: $f is the new package's"; done
	check '! grep -q "Your changes" $T/up.log' "untouched: nothing said"
	check '[ -z "$(ls -d /etc/*.dpkg-* /etc/skel/*.dpkg-* /etc/zsh/*.dpkg-* /etc/update-motd.d/*.dpkg-* /var/lib/'$PKG'/held 2>/dev/null)" ]' "untouched: nothing left beside the files"
	check '[ $vrc = 0 ] && ! grep -q -E "^(CHANGED|LCCHANGED|EDITED|MISSING)" $T/verify.txt' "untouched: dpkg-stereo --verify clean (rc $vrc)"
	for f in $EIGHT; do check '! named "$f"' "untouched: --verify and --deep say nothing of $f"; done
	view $T/view-after.txt
	check 'cmp -s $T/view-before.txt $T/view-after.txt' "untouched: the login texts, the message of the day, a new account's home and the shell settings are the same"
else
	for f in $EIGHT; do check '[ "$(sha "$f")" = "$(sha "$T/before/${f//\//_}")" ]' "edited: the person's $f kept byte for byte"; done
	for f in $EIGHT; do
		case $f in /etc/skel/*) d=/var/backups/$PKG$f.dpkg-dist ;; *) d=$f.dpkg-dist ;; esac
		check '[ "$(grep -c -F "Your changes to $f are kept; the new default is in $d." $T/up.log)" = 1 ] && [ "$(sha "$d")" = "$(sha "$(ref "$f")")" ]' "edited: $f said once, the new default at $d"
	done
	check '[ -z "$(ls /etc/skel | grep dpkg)" ]' "edited: nothing new in /etc/skel for useradd to copy"
	for f in $EIGHT; do check 'named "$f"' "edited: dpkg-stereo --verify or --deep names $f"; done
fi
dpkg -r $PKG >$T/remove.log 2>&1; rc=$?
check '[ $rc = 0 ]' "removal: rc $rc"
for f in $FIVE; do check '[ -z "$(dpkg-divert --listpackage "$f")" ] && [ ! -e "$f.debian" ] && [ -e "$f" ] && ! grep -q "a person" "$f"' "removal: the owning package's $f back at its name"; done
if [ "$CASE" = up-edited ]; then
	for f in $FIVE; do check '[ "$(sha "/var/backups/'$PKG'$f")" = "$(sha "$T/before/${f//\//_}")" ] && grep -q -F "Your changes to $f are kept in /var/backups/'$PKG'$f." $T/remove.log' "removal: the person's $f kept in /var/backups/$PKG$f and said"; done
fi
dpkg --purge $PKG >$T/purge.log 2>&1; rc=$?
check '[ $rc = 0 ] && [ ! -e /var/lib/'$PKG' ] && [ ! -e /etc/skel/.selected_editor ] && cmp -s /etc/motd /usr/share/base-files/motd' "purge: rc $rc, the state gone, Debian's motd back"
exit $failed
