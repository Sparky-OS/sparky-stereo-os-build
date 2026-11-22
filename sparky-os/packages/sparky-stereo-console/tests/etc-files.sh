#!/bin/bash
# sparky-stereo-console: a person's change to the console's eight files under /etc is kept across upgrades (row 813).
# Root, in a throwaway container of the published edition (the console and its diversions installed), no network.
#   etc-files.sh CASE NEW [FROM]
#     CASE  up-none     upgrade, nothing changed: every file is the new package's, nothing said, nothing asked,
#                       what a login and a new account show is unchanged; then removal and purge
#           up-edited   a person's change planted in each of the eight files before the upgrade: each kept byte
#                       for byte, the new default beside it and said once, nothing asked, each named by
#                       dpkg-stereo --verify (or --verify --deep); then removal and purge
#                       TTY=1: the upgrade runs at a pseudo-terminal with debconf's readline frontend, so any question
#                       waits for an answer and the run fails at its time limit; ROUND=1: with the round's
#                       --force-confdef --force-confold (dpkg hands them to ucf as DPKG_FORCE)
#           fresh       the published console purged first, then the package under test installed
#           zsh-later   upgrade as up-none, then zsh-common installed afterwards (ZSH_COMMON: its .deb) and purged again:
#                       our /etc/zsh/zshrc and ucf's record of it unchanged throughout, zsh-common's own file at the
#                       diverted name while it is installed, dpkg-stereo --verify clean; then removal and purge
#           half        a person's change to /etc/zsh/zshrc, then FROM (20261122) whose configure fails on a system without
#                       zsh-common, then the package under test: it configures and the change is kept
#           say         the sentences in the ten languages
#     Every case also runs on a system without zsh-common or nano (continuation 14: on such a machine the published
#     console was the only owner of /etc/zsh): a file's owning package that is not installed has nothing at the
#     diverted name and nothing at the name after the removal; every folder that holds one of the eight is in an
#     installed package's list after the install; no empty folder of ours is left after the upgrade, the removal or
#     the purge, and nothing of another package's goes.
#     NEW   a folder with the package under test and its -lc-hr companion; FROM: a folder installed first
# apt runs carry no --force-conf* (unless ROUND=1) and read /dev/null: a dpkg question fails the run. The five at
# diverted names are kept through ucf (its records in /var/lib/ucf). Exit 1 on any FAIL.
set -u
CASE=$1 NEW=$(readlink -f "$2") FROM=${3:-}
PKG=sparky-stereo-console
EIGHT="/etc/issue /etc/issue.net /etc/motd /etc/nanorc /etc/zsh/zshrc /etc/update-motd.d/10-uname /etc/skel/.bash_aliases /etc/skel/.selected_editor"
FIVE="/etc/issue /etc/issue.net /etc/update-motd.d/10-uname /etc/nanorc /etc/zsh/zshrc"
T=/tmp/etc-files; rm -rf $T; mkdir -p $T/ref $T/before
failed=0
check() { if eval "$1"; then echo "PASS $2"; else echo "FAIL $2"; failed=1; fi; }
apt_y() { apt-get -y -q -o Dpkg::Use-Pty=0 -o APT::Color=0 "$@" </dev/null; }
apt_up() { # the upgrade under test: plain, or at a pseudo-terminal (TTY=1), with the round's flags (ROUND=1)
	a="-y -q -o Dpkg::Use-Pty=0 -o APT::Color=0"
	[ "${ROUND:-}" != 1 ] || a="$a -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
	if [ "${TTY:-}" = 1 ]; then
		DEBIAN_FRONTEND=readline TERM=xterm timeout 300 script -qec "apt-get $a install $*" /dev/null </dev/null | tr -d '\r'
		return "${PIPESTATUS[0]}"
	fi
	apt-get $a install "$@" </dev/null
}
ucf_sum() { awk -v p="$1" '$2 == p {print $1; exit}' /var/lib/ucf/hashfile 2>/dev/null; }
ucf_pkg() { awk -v p="$1" '$NF == p {print $1; exit}' /var/lib/ucf/registry 2>/dev/null; }
ucf_ours() { grep -l -F -e /etc/issue -e /etc/nanorc -e /etc/zsh/zshrc -e /etc/update-motd.d/10-uname /var/lib/ucf/hashfile /var/lib/ucf/registry 2>/dev/null; ls /var/lib/ucf/cache 2>/dev/null | grep -E '^:etc:(issue|issue.net|nanorc|zsh:zshrc|update-motd.d:10-uname)$'; }
sha() { sha256sum <"$1" 2>/dev/null | cut -c1-64; }
asked() { grep -c -E 'Configuration file|end of file on <standard input>|Modified locally|Deleted locally|What do you want to do about modified configuration file|locally modified|Need debconf to interact' "$1"; }
dpkg-deb -x "$NEW/${PKG}_"*_all.deb $T/ref
ref() { case $1 in /etc/motd|/etc/skel/*) echo "$T/ref$1" ;; *) echo "$T/ref/usr/share/$PKG/defaults$1" ;; esac; }
view() { # view FILE HOME-FILE: what a login shows (the login texts, the message of the day, nano, zsh), and a new home
	{ for f in /etc/issue /etc/issue.net /etc/motd; do echo "== $f"; cat "$f"; done
	  echo '== 10-uname'; sh /etc/update-motd.d/10-uname
	  echo '== nano'; cat /etc/nanorc
	  echo '== zsh'; cat /etc/zsh/zshrc; } >"$1" 2>&1
	u=u$RANDOM; useradd -m -s /bin/bash "$u" && { echo "== home"; ls -A "/home/$u"
	  for f in .bash_aliases .selected_editor .bashrc; do echo "== $f"; cat "/home/$u/$f" 2>/dev/null; done; userdel -r "$u" 2>/dev/null; } >"$2" 2>&1; }
owner_of() { case $1 in /etc/nanorc) echo nano ;; /etc/zsh/zshrc) echo zsh-common ;; *) echo base-files ;; esac; }
installed() { [ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" = "ii " ]; }
listed_by() { dpkg-query -S "$1" 2>/dev/null | sed 's/: [^:]*$//' | tr ',' '\n' | tr -d ' ' | grep -v -x -e '' | sort -u | tr '\n' ' '; }
# the folders that hold one of the eight files, each in the list of a package that is installed (dpkg never removes it)
unowned_folders() { for f in $EIGHT; do d=${f%/*}; for p in $(listed_by "$d"); do installed "$p" && continue 2; done; echo "$d"; done | sort -u | tr '\n' ' '; }
# an empty folder this package shipped or its scripts made, that no other package lists
empty_ours() {
	for d in /etc/zsh /etc/update-motd.d /etc/skel /var/lib/$PKG $(find /var/backups/$PKG -type d 2>/dev/null); do
		[ -d "$d" ] && [ -z "$(ls -A "$d")" ] || continue
		[ -n "$(listed_by "$d" | tr ' ' '\n' | grep -v -x -e '' -e "$PKG")" ] || echo "$d"
	done | tr '\n' ' '
}
# a path of an installed owning package's list in the console's folders that is gone (a diverted one at its diverted name)
owners_missing() {
	for o in base-files nano zsh-common bash; do
		installed "$o" || continue
		dpkg -L "$o" | grep -E '^/etc/(zsh|update-motd\.d|skel)(/|$)|^/etc/(issue|issue\.net|nanorc)$' | while read -r q; do
			t=$(dpkg-divert --truename "$q")
			[ -e "$t" ] || [ -L "$t" ] || echo "$o:$q"
		done
	done | tr '\n' ' '
}
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
	[ $rc = 0 ] || grep -E 'cannot create|error processing|returned error' $T/install.log | head -4 | sed 's/^/INFO   /'
	check '[ $rc = 0 ] && [ "$(asked $T/install.log)" = 0 ]' "fresh install: rc $rc, nothing asked"
	for f in $EIGHT; do check '[ "$(sha "$f")" = "$(sha "$(ref "$f")")" ]' "fresh: $f is the package's"; done
	for f in /etc/issue:base-files /etc/issue.net:base-files /etc/update-motd.d/10-uname:base-files /etc/nanorc:nano /etc/zsh/zshrc:zsh-common; do
		p=${f%%:*} o=${f#*:}
		if ! installed "$o"; then check '[ ! -e "$p.debian" ] && [ "$(dpkg-divert --listpackage "$p")" = $PKG ]' "fresh: $o is not installed: nothing at $p.debian"; continue; fi
		h=$(dpkg-query -W -f='${Conffiles}\n' "$o" 2>/dev/null | awk -v p="$p" '$1 == p {print $2}')
		check '[ -n "$h" ] && [ "$h" != newconffile ] && [ "$(md5sum <"$p.debian" | cut -d" " -f1)" = "$h" ]' "fresh: $o's $p kept at $p.debian with its hash ($h)"
	done
	check '[ -z "$(unowned_folders)" ]' "fresh: every folder that holds one of the eight is in an installed package's list (none: $(unowned_folders))"
	check '[ -z "$(empty_ours)" ]' "fresh: no empty folder of ours ($(empty_ours))"
	check '! grep -q "Your changes" $T/install.log' "fresh: nothing said"
	for f in $FIVE; do check '[ "$(ucf_sum "$f")" = "$(md5sum <"$f" | cut -d" " -f1)" ] && [ "$(ucf_pkg "$f")" = $PKG ]' "fresh: ucf records $f for $PKG with what it wrote"; done
	check '[ "$(stat -c %a /etc/update-motd.d/10-uname)" = 755 ]' "fresh: 10-uname is executable"
	exit $failed
fi

if [ "$CASE" = half ]; then
	# a machine where FROM's configure failed (20261122 on a system without zsh-common: dpkg had removed /etc/zsh), a
	# person's change to /etc/zsh/zshrc made before it; then the package under test
	z=/etc/zsh/zshrc
	printf '# a person'"'"'s change to %s\n' $z >>$z; cp -p $z $T/before/z
	apt_y install "$FROM"/*.deb >$T/from.log 2>&1; rc=$?
	check '[ $rc != 0 ] && [ "$(dpkg-query -W -f="\${Status}" $PKG)" != "install ok installed" ]' "the run that failed: rc $rc, $(dpkg-query -W -f='${Version} ${Status}' $PKG)"
	grep -E 'cannot create|error processing' $T/from.log | head -3 | sed 's/^/INFO   /'
	apt_up "$NEW"/*.deb >$T/up.log 2>&1; rc=$?
	echo "to: $(dpkg-query -W -f='${Version}' $PKG)"
	check '[ $rc = 0 ] && [ "$(asked $T/up.log)" = 0 ] && [ "$(dpkg-query -W -f="\${Status}" $PKG)" = "install ok installed" ] && [ -z "$(dpkg --audit 2>&1)" ]' "the next run: rc $rc, nothing asked, installed, dpkg --audit empty"
	check '[ "$(sha $z)" = "$(sha $T/before/z)" ] && [ "$(grep -c -F "Your changes to $z are kept; the new default is in $z.ucf-dist." $T/up.log)" = 1 ] && [ "$(sha $z.ucf-dist)" = "$(sha "$(ref $z)")" ]' "the next run: the person's $z kept byte for byte, said once, the new default at $z.ucf-dist"
	check '[ "$(ucf_pkg $z)" = $PKG ] && [ "$(ucf_sum $z)" = "$(md5sum <"$(ref $z)" | cut -d" " -f1)" ]' "the next run: ucf records the new default for $z"
	for f in $FIVE; do [ $f = $z ] || check '[ "$(sha "$f")" = "$(sha "$(ref "$f")")" ] && [ "$(ucf_pkg "$f")" = $PKG ]' "the next run: $f is the package's, kept through ucf"; done
	check '[ -z "$(unowned_folders)" ] && [ -z "$(empty_ours)" ] && [ ! -e /var/lib/'$PKG'/held ]' "the next run: every folder in an installed package's list, no empty folder of ours, nothing held ($(unowned_folders)$(empty_ours))"
	dpkg-stereo --verify >$T/verify.txt 2>&1; : >$T/deep.txt
	check 'named $z' "the next run: dpkg-stereo --verify names $z"
	exit $failed
fi
[ -n "$FROM" ] && { apt_y install "$FROM"/*.deb >$T/from.log 2>&1 || { echo "FAIL installing FROM"; tail -3 $T/from.log; exit 1; }; }
echo "from: $(dpkg-query -W -f='${Version}' $PKG)"
view $T/view-before.txt $T/home-before.txt
if [ "$CASE" = up-edited ]; then
	for f in $EIGHT; do mkdir -p "${f%/*}"; [ -e "$f" ] || : >"$f"; printf '# a person'"'"'s change to %s\n' "$f" >>"$f"; cp -p "$f" "$T/before/${f//\//_}"; done
fi
apt_up "$NEW"/*.deb >$T/up.log 2>&1; rc=$?
echo "to: $(dpkg-query -W -f='${Version}' $PKG)"
[ $rc = 0 ] || grep -E 'cannot create|error processing|returned error' $T/up.log | head -4 | sed 's/^/INFO   /'
check '[ $rc = 0 ] && [ "$(asked $T/up.log)" = 0 ]' "upgrade: rc $rc, nothing asked"
check '[ "$(dpkg-query -W -f="\${Status}" $PKG)" = "install ok installed" ] && [ -z "$(dpkg --audit 2>&1)" ]' "upgrade: installed, dpkg --audit empty"
dpkg-stereo --verify >$T/verify.txt 2>&1; vrc=$?
# --deep reads a package's own .deb from APT's cache; the package under test is put there for the run (no network)
cp "$NEW"/*.deb /var/cache/apt/archives/
dpkg-stereo --deep --verify $PKG $(for o in base-files nano zsh-common; do installed "$o" && echo "$o"; done) >$T/deep.txt 2>&1
rm -f /var/cache/apt/archives/"$PKG"*.deb
echo "INFO zsh-common $(installed zsh-common && echo installed || echo 'not installed'), nano $(installed nano && echo installed || echo 'not installed')"
check '[ -z "$(unowned_folders)" ]' "upgrade: every folder that holds one of the eight is in an installed package's list (none: $(unowned_folders))"
check '[ -z "$(empty_ours)" ]' "upgrade: no empty folder of ours ($(empty_ours))"
check '[ -z "$(owners_missing)" ]' "upgrade: every path of the owning packages in these folders is there ($(owners_missing))"
if [ "$CASE" = up-none ] || [ "$CASE" = zsh-later ]; then
	for f in $EIGHT; do check '[ "$(sha "$f")" = "$(sha "$(ref "$f")")" ]' "untouched: $f is the new package's"; done
	check '! grep -q "Your changes" $T/up.log' "untouched: nothing said"
	check '[ -z "$(ls -d /etc/*.dpkg-* /etc/skel/*.dpkg-* /etc/zsh/*.dpkg-* /etc/update-motd.d/*.dpkg-* /etc/*.ucf-* /etc/zsh/*.ucf-* /etc/update-motd.d/*.ucf-* /var/lib/'$PKG'/held 2>/dev/null)" ]' "untouched: nothing left beside the files"
	for f in $FIVE; do check '[ "$(ucf_sum "$f")" = "$(md5sum <"$(ref "$f")" | cut -d" " -f1)" ] && [ "$(ucf_pkg "$f")" = $PKG ]' "untouched: ucf records $f for $PKG with the new default"; done
	check '[ "$(stat -c %a /etc/update-motd.d/10-uname)" = 755 ]' "untouched: 10-uname is executable"
	check '[ $vrc = 0 ] && ! grep -q -E "^(CHANGED|LCCHANGED|EDITED|MISSING)" $T/verify.txt' "untouched: dpkg-stereo --verify clean (rc $vrc)"
	for f in $EIGHT; do check '! named "$f"' "untouched: --verify and --deep say nothing of $f"; done
	view $T/view-after.txt $T/home-after.txt
	check 'cmp -s $T/view-before.txt $T/view-after.txt' "untouched: the login texts, the message of the day, nanorc and zshrc are byte for byte the same"
	# from 20261102 a new home differs by design (20261121: .bash_aliases in place of the diverted .bashrc, REPORT-3)
	[ -z "$FROM" ] || check 'cmp -s $T/home-before.txt $T/home-after.txt' "untouched: a new account's home is byte for byte the same"
else
	for f in $EIGHT; do check '[ "$(sha "$f")" = "$(sha "$T/before/${f//\//_}")" ]' "edited: the person's $f kept byte for byte"; done
	for f in $EIGHT; do
		case $f in /etc/skel/*) d=/var/backups/$PKG$f.dpkg-dist ;; /etc/motd) d=$f.dpkg-dist ;; *) d=$f.ucf-dist ;; esac
		check '[ "$(grep -c -F "Your changes to $f are kept; the new default is in $d." $T/up.log)" = 1 ] && [ "$(sha "$d")" = "$(sha "$(ref "$f")")" ]' "edited: $f said once, the new default at $d"
	done
	check '[ -z "$(ls /etc/skel | grep dpkg)" ]' "edited: nothing new in /etc/skel for useradd to copy"
	check '[ "$(stat -c %a /etc/update-motd.d/10-uname.ucf-dist)" = 644 ] && run-parts --lsbsysinit --test /etc/update-motd.d | grep -q -x /etc/update-motd.d/10-uname && ! run-parts --lsbsysinit --test /etc/update-motd.d | grep -q ucf-dist' "edited: run-parts runs 10-uname and not the default beside it"
	for f in $FIVE; do check '[ "$(ucf_pkg "$f")" = $PKG ] && [ "$(ucf_sum "$f")" = "$(md5sum <"$(ref "$f")" | cut -d" " -f1)" ] && [ "$(ucf_sum "$f")" != "$(md5sum <"$f" | cut -d" " -f1)" ]' "edited: ucf records the new default for $f, which differs from the person's"; done
	for f in $EIGHT; do check 'named "$f"' "edited: dpkg-stereo --verify or --deep names $f"; done
fi
if [ "$CASE" = zsh-later ]; then
	z=/etc/zsh/zshrc; was=$(sha $z)
	# zsh-common alone carries /etc/zsh; its Recommends (zsh) is not at hand with no network
	apt_y install --no-install-recommends "${ZSH_COMMON:?}" >$T/zc.log 2>&1; rc=$?
	[ $rc = 0 ] || grep -E '^E: |error|cannot' $T/zc.log | head -4 | sed 's/^/INFO   /'
	check '[ $rc = 0 ] && [ "$(asked $T/zc.log)" = 0 ] && installed zsh-common' "zsh-common installed afterwards: rc $rc, nothing asked"
	h=$(dpkg-query -W -f='${Conffiles}\n' zsh-common | awk -v p=$z '$1 == p {print $2}')
	check '[ "$(sha $z)" = "$was" ] && [ "$(ucf_pkg $z)" = $PKG ] && [ "$(ucf_sum $z)" = "$(md5sum <$z | cut -d" " -f1)" ]' "zsh-common installed: our $z unchanged and ucf's record of it ours"
	check '[ -n "$h" ] && [ "$h" != newconffile ] && [ "$(md5sum <$z.debian | cut -d" " -f1)" = "$h" ]' "zsh-common installed: its own $z at $z.debian with its hash ($h)"
	dpkg-stereo --verify >$T/verify-zc.txt 2>&1; zrc=$?
	check '[ $zrc = 0 ] && ! grep -q -E "^(CHANGED|LCCHANGED|EDITED|MISSING)" $T/verify-zc.txt' "zsh-common installed: dpkg-stereo --verify clean (rc $zrc)"
	zh=$(md5sum <$z.debian | cut -d" " -f1)
	dpkg --purge zsh-common >$T/zc-purge.log 2>&1; rc=$?
	echo "INFO dpkg at zsh-common's purge: $(grep -i -E 'warning|not empty' $T/zc-purge.log | tr '\n' ' ')"
	check '[ $rc = 0 ] && ! installed zsh-common && [ "$(sha $z)" = "$was" ] && [ "$(ucf_pkg $z)" = $PKG ] && [ "$(ucf_sum $z)" = "$(md5sum <$z | cut -d" " -f1)" ] && [ -z "$(unowned_folders)" ]' "zsh-common purged again: rc $rc, our $z unchanged and kept through ucf, its folder still in an installed package's list"
	# dpkg's purge drops a conffile from its list while another package's diversion covers it (src/main/remove.c), so
	# zsh-common's own file stays at the diverted name; the removal below gives it back at its name, as for any owner
	left=; [ ! -e $z.debian ] || left=$(md5sum <$z.debian | cut -d" " -f1)
	echo "INFO after zsh-common's purge, $z.debian: ${left:-gone}$([ "$left" = "$zh" ] && echo " (zsh-common's own file, left by dpkg's purge under the diversion)")"
	dpkg-stereo --verify >$T/verify-zc2.txt 2>&1; zrc=$?
	check '[ $zrc = 0 ] && ! grep -q -E "^(CHANGED|LCCHANGED|EDITED|MISSING)" $T/verify-zc2.txt' "zsh-common purged again: dpkg-stereo --verify clean (rc $zrc)"
fi
dpkg -r $PKG >$T/remove.log 2>&1; rc=$?
check '[ $rc = 0 ]' "removal: rc $rc"
for f in $FIVE; do
	o=$(owner_of "$f")
	if installed "$o"; then check '[ -z "$(dpkg-divert --listpackage "$f")" ] && [ ! -e "$f.debian" ] && [ -e "$f" ] && ! grep -q "a person" "$f"' "removal: $o's $f back at its name"
	elif [ "$f" = /etc/zsh/zshrc ] && [ -n "${zh:-}" ]; then check '[ -z "$(dpkg-divert --listpackage "$f")" ] && [ ! -e "$f.debian" ] && { [ ! -e "$f" ] || [ "$(md5sum <"$f" | cut -d" " -f1)" = "$zh" ]; }' "removal: $o purged under the diversion: at $f only what dpkg left of its own ($( [ -e "$f" ] && echo "its file" || echo nothing))"
	else check '[ -z "$(dpkg-divert --listpackage "$f")" ] && [ ! -e "$f.debian" ] && [ ! -e "$f" ] && [ ! -L "$f" ]' "removal: $o is not installed: nothing left at $f"; fi
done
check '[ -z "$(empty_ours)" ]' "removal: no empty folder of ours ($(empty_ours))"
check '[ -z "$(owners_missing)" ]' "removal: nothing of the owning packages gone ($(owners_missing))"
if [ "$CASE" = up-edited ]; then
	for f in $FIVE; do check '[ "$(sha "/var/backups/'$PKG'$f")" = "$(sha "$T/before/${f//\//_}")" ] && grep -q -F "Your changes to $f are kept in /var/backups/'$PKG'$f." $T/remove.log' "removal: the person's $f kept in /var/backups/$PKG$f and said"; done
fi
check '[ -z "$(ucf_ours)" ] && [ -z "$(ls -d /etc/*.ucf-* /etc/zsh/*.ucf-* /etc/update-motd.d/*.ucf-* 2>/dev/null)" ]' "removal: ucf's records of the five gone (hashfile, registry, cache), nothing beside the files"
if [ "$CASE" = up-none ]; then
	apt_y install "$NEW"/*.deb >$T/reinstall.log 2>&1; rc=$?
	for f in $FIVE; do check '[ $rc = 0 ] && [ "$(sha "$f")" = "$(sha "$(ref "$f")")" ] && [ "$(ucf_pkg "$f")" = $PKG ]' "reinstall after the removal: $f is the package's again, kept through ucf"; done
	dpkg -r $PKG >$T/remove2.log 2>&1
fi
dpkg --purge $PKG >$T/purge.log 2>&1; rc=$?
check '[ $rc = 0 ] && [ ! -e /var/lib/'$PKG' ] && [ ! -e /etc/skel/.selected_editor ] && cmp -s /etc/motd /usr/share/base-files/motd' "purge: rc $rc, the state gone, Debian's motd back"
check '[ -z "$(ucf_ours)" ]' "purge: nothing of the five in ucf's hashfile, registry or cache"
check '[ -z "$(empty_ours)" ] && [ -z "$(owners_missing)" ]' "purge: no empty folder of ours ($(empty_ours)), nothing of the owning packages gone ($(owners_missing))"
echo "INFO dpkg at the purge: $(grep -i -E 'warning|not empty' $T/purge.log | tr '\n' ' ')"
echo "INFO ucf's own rotated copies that still name one of the five: $(grep -l -F -e /etc/issue -e /etc/nanorc /var/lib/ucf/hashfile.* /var/lib/ucf/registry.* 2>/dev/null | tr '\n' ' ')"
exit $failed
