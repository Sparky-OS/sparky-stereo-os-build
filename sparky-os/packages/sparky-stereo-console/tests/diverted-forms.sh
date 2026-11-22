#!/bin/bash
# sparky-stereo-console (row 813): which way can a file at a name the package diverts keep a person's edit?
# Fixtures, built in the container from the console's own maintainer-script templates (TPL, read only):
#   c11own 1.0   the owning package: conffile /etc/c11.conf
#   c11div 1.0   the form up to 20261121.1: plain /etc/c11.conf (diverted, the safe form F2) and plain /etc/c11-plain
#                (the same templates with no conffiles and no files kept by the scripts)
#   c11div 2.0C  both files conffiles (the conffile way for the diverted name too)
#   c11div 2.0S  /etc/c11-plain a conffile, /etc/c11.conf made and kept by the postinst (the maintainer-script way)
#   c11div 2.1C/2.1S  the same with new defaults
# Every apt run: no --force-conf*, stdin from /dev/null, so a dpkg question fails the run.
# Root, throwaway container of the published edition, dpkg-stereo under test at /ds. Usage: CASE=FORM:fresh:WAY|FORM:up:EDIT TPL=RECIPE diverted-forms.sh (FORM C or S; WAY apt own-first dpkg-AB dpkg-BA
# dpkg-A-B; EDIT none edited). Expected: C fails (a question, a failed removal, the owner's file lost at purge); S passes
set -u
dpkg -i /ds/dpkg-stereo_*_all.deb </dev/null >/dev/null 2>&1 || echo "dpkg-stereo install failed"
TPL=${TPL:-/tpl}
W=/tmp/c11; rm -rf "$W"; mkdir -p "$W/repo" "$W/b"
P=/etc/c11.conf PL=/etc/c11-plain
say() { printf '%s\n' "$*"; }
mk() { # mk NAME VERSION DIR: md5sums of every file but the conffiles, as the console's recipe writes them
	(cd "$3" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort |
		grep -v -x -F -f <(sed 's|^/||' DEBIAN/conffiles 2>/dev/null; echo DEBIAN/none) | xargs -r md5sum >DEBIAN/md5sums)
	dpkg-deb --root-owner-group -b "$3" "$W/b/$1_$2_all.deb" >/dev/null; }
own() { d=$W/own; rm -rf "$d"; mkdir -p "$d/DEBIAN" "$d/etc"
	printf 'owner %s\n' "$1" >"$d$P"; echo "$P" >"$d/DEBIAN/conffiles"
	printf 'Package: c11own\nVersion: %s\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: owner\n' "$1" >"$d/DEBIAN/control"
	mk c11own "$1" "$d"; }
tpl() { # tpl FILE OUT CONFF MANAGED: the console's templates with this fixture's names
	sed -e 's|@PACKAGE@|c11div|g' -e "s|@DIVERTED@|$P|g" -e 's|@GIVEN_BACK@||g' -e 's|@FIRST@|2.0~|g' \
		-e "s|@CONFF@|$3|g" -e "s|@MANAGED@|$4|g" "$1" >"$2"; chmod 755 "$2"; }
div() { # div VERSION FORM(0|C|S)
	d=$W/div-$1; rm -rf "$d"; mkdir -p "$d/DEBIAN" "$d/etc"
	printf 'Package: c11div\nVersion: %s\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: diverts (%s)\n' "$1" "$2" >"$d/DEBIAN/control"
	printf 'ours plain %s\n' "$1" >"$d$PL"
	case $2 in
	0) printf "ours %s\n" "$1" >"$d$P"
	   for s in preinst postinst postrm; do tpl "$TPL/$s.in" "$d/DEBIAN/$s" "" ""; done ;;
	C) printf 'ours %s\n' "$1" >"$d$P"; printf '%s\n' "$PL" "$P" >"$d/DEBIAN/conffiles"
	   for s in preinst postinst postrm; do tpl "$TPL/$s.in" "$d/DEBIAN/$s" "$PL $P" ""; done ;;
	S) mkdir -p "$d/usr/share/c11div/defaults/etc"; printf 'ours %s\n' "$1" >"$d/usr/share/c11div/defaults$P"; echo "$PL" >"$d/DEBIAN/conffiles"
	   for s in preinst postinst postrm; do tpl "$TPL/$s.in" "$d/DEBIAN/$s" "$PL" "$P"; done ;;
	esac
	mk c11div "$1" "$d"; }
index() { (cd "$W/repo" && dpkg-scanpackages -m . >Packages 2>/dev/null && gzip -kf Packages && xz -kf Packages); }
repo() { rm -f "$W/repo/"*; cp "$@" "$W/repo/"; index
	echo "deb [trusted=yes] file:$W/repo ./" >"$W/lc.list"
	apt-get -q -o Dir::Etc::SourceList="$W/lc.list" -o Dir::Etc::SourceParts=- -o APT::Get::List-Cleanup=0 update >/dev/null 2>&1; }
aptx() { apt-get -y -o Dpkg::Use-Pty=0 -o Dir::Etc::SourceList="$W/lc.list" -o Dir::Etc::SourceParts=- "$@" </dev/null >>"$W/log" 2>&1; }
clean() { dpkg --purge c11div c11own >/dev/null 2>&1; rm -rf $P $P.* $PL $PL.* /var/lib/c11div /var/backups/c11div; : >"$W/log"; }
state() { # state LABEL
	h=$(dpkg-query -W -f='${Conffiles}\n' c11own 2>/dev/null | awk -v p=$P '$1 == p {print $2 ($3 ? " " $3 : "")}')
	dh=$(dpkg-query -W -f='${Conffiles}\n' c11div 2>/dev/null | awk '{printf "%s=%s%s ", $1, substr($2,1,8), ($3 ? "," $3 : "")}')
	st=$(dpkg-query -W -f='${Status} ${Version}' c11div 2>/dev/null)
	q=$(grep -c -E "Configuration file|Deleted locally|Modified locally|end of file on stdin" "$W/log")
	said=$(grep -h '^c11div: ' "$W/log" | tr '\n' ' ')
	v=$(dpkg-stereo --verify c11own c11div 2>&1 | grep -E '^(CHANGED|LCCHANGED|EDITED|MISSING|AFTERINST)' | tr '\n' ';')
	vd=$(dpkg-stereo --verify --deep c11own c11div 2>&1 | grep -E '^(CHANGED|LCCHANGED|EDITED|MISSING|AFTERINST)' | tr '\n' ';')
	dv=$(dpkg --verify c11own c11div 2>&1 | tr '\n' ';')
	[ "$rc" = 0 ] || { say "   log of a failed run:"; tail -6 "$W/log" | sed 's/^/   | /'; }
	say "$1: rc=$rc div[$st] own-hash=${h:-none} | $P=$(cat $P 2>/dev/null || echo absent) | $P.debian=$(cat $P.debian 2>/dev/null || echo absent) | $PL=$(cat $PL 2>/dev/null || echo absent) | div-conffiles: ${dh:-none}| questions=$q | said: ${said:-nothing} | dists: $(ls $P.dpkg-* $PL.dpkg-* /var/backups/c11div/etc/* 2>/dev/null | tr '\n' ' ') | dpkg-stereo verify: ${v:-clean} deep: ${vd:-clean} | dpkg --verify: ${dv:-clean}"; }
own 1.0
div 1.0 0; div 2.0 C; mv "$W/b/c11div_2.0_all.deb" "$W/b/c11div_2.0C.deb"; div 2.1 C; mv "$W/b/c11div_2.1_all.deb" "$W/b/c11div_2.1C.deb"
div 2.0 S; mv "$W/b/c11div_2.0_all.deb" "$W/b/c11div_2.0S.deb"; div 2.1 S; mv "$W/b/c11div_2.1_all.deb" "$W/b/c11div_2.1S.deb"
IFS=: read -r F K X <<<"${CASE:?FORM:fresh:WAY or FORM:up:EDIT}"
if [ "$K" = fresh ]; then
	way=$X
	say "== form $F: fresh install, $way"
	clean; repo "$W/b/c11own_1.0_all.deb"; cp "$W/b/c11div_2.0$F.deb" "$W/repo/c11div_2.0_all.deb"; index
	dv="$W/repo/c11div_2.0_all.deb" ow="$W/repo/c11own_1.0_all.deb"
	case $way in
	apt) aptx install "$ow" "$dv"; rc=$? ;;
	own-first) dpkg -i "$ow" </dev/null >>"$W/log" 2>&1; aptx install "$dv"; rc=$? ;;
	dpkg-AB) dpkg --unpack "$ow" "$dv" </dev/null >>"$W/log" 2>&1; dpkg --configure -a </dev/null >>"$W/log" 2>&1; rc=$? ;;
	dpkg-BA) dpkg --unpack "$dv" "$ow" </dev/null >>"$W/log" 2>&1; dpkg --configure -a </dev/null >>"$W/log" 2>&1; rc=$? ;;
	dpkg-A-B) dpkg --unpack "$ow" </dev/null >>"$W/log" 2>&1; dpkg --unpack "$dv" </dev/null >>"$W/log" 2>&1; dpkg --configure -a </dev/null >>"$W/log" 2>&1; rc=$? ;;
	esac
	grep -E '^(Unpacking|Setting up) c11' "$W/log" | sed 's/ (.*//' | tr '\n' ';' | sed 's/^/   order: /'; echo
	state "$F fresh $way"
	[ "$rc" = 0 ] && { : >"$W/log"; dpkg -r c11div </dev/null >>"$W/log" 2>&1; rc=$?; state "$F fresh-$way removed"; : >"$W/log"; dpkg --purge c11div </dev/null >>"$W/log" 2>&1; rc=$?; state "$F fresh-$way purged"; }
	exit 0
fi
edit=$X
say "== form $F: upgrade from today's form (1.0), $edit"
clean; dpkg -i "$W/b/c11own_1.0_all.deb" </dev/null >"$W/log0" 2>&1; dpkg -i "$W/b/c11div_1.0_all.deb" </dev/null >>"$W/log0" 2>&1 || { echo "1.0 install failed"; tail -5 "$W/log0"; }
[ $edit = edited ] && { echo 'person edit' >>$P; echo 'person edit' >>$PL; }
rc=0; state "$F before-$edit"
cp "$W/b/c11div_2.0$F.deb" "$W/c11div_2.0_all.deb"
: >"$W/log"; aptx install "$W/c11div_2.0_all.deb"; rc=$?; state "$F up-1.0-$edit"
[ $rc = 0 ] || dpkg --configure -a --force-confdef --force-confold </dev/null >>"$W/log" 2>&1
say "-- then 2.1 (new defaults)"; : >"$W/log"
cp "$W/b/c11div_2.1$F.deb" "$W/c11div_2.1_all.deb"
aptx install "$W/c11div_2.1_all.deb"; rc=$?; state "$F up-2.1-$edit"
[ $rc = 0 ] || { : >"$W/log"; dpkg --configure -a --force-confdef --force-confold </dev/null >>"$W/log" 2>&1; rc=$?; state "$F up-2.1-$edit, configured with --force-confdef --force-confold"; }
say "-- then removal"; : >"$W/log"; dpkg -r c11div </dev/null >>"$W/log" 2>&1; rc=$?; state "$F removed-$edit"
say "-- then purge"; : >"$W/log"; dpkg --purge c11div </dev/null >>"$W/log" 2>&1; rc=$?; state "$F purged-$edit"
