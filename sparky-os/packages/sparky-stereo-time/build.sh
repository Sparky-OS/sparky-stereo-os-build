#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-time: chrony's time sources from the timezone. The country's official
# service (NTS where it offers it) from a TSV of verified rows, else Debian's pool. A oneshot
# service runs at boot before chrony; a watcher runs it again when timedated reports a new timezone;
# a timer checks after the start and every hour that the chosen servers answer. What fails is said and
# kept by the edition's one engine, sparky-stereo-problems (lib/problems.py, ORDER 350), whose notifier shows
# it in the session; the messages are built into journal catalogs by its catalog command.
# Needs dpkg-deb and sparky-stereo-problems; run it in a throwaway container or on any Debian.
# Last update 2026/11/02
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
VERSION=20261102~sparky9~0+lc1
PKG=sparky-stereo-time
W=$(mktemp -d "${TMPDIR:-${SPARKY_SCRATCH:?}}/time-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
S=$D/usr/share/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/bin" "$S" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" "$D/usr/lib/$PKG" \
	"$D/etc/chrony/conf.d" "$D/usr/lib/systemd/system/multi-user.target.wants" "$D/usr/lib/systemd/system/timers.target.wants" \
	"$D/usr/lib/systemd/catalog"

install -m 755 "$HERE/bin/sparky-stereo-time" "$HERE/bin/sparky-stereo-time-watch" "$D/usr/bin/"
install -m 755 "$HERE/lib/problems.py" "$D/usr/lib/$PKG/problems.py"
install -m 644 "$HERE/data/ntp-countries.tsv" "$S/ntp-countries.tsv"
install -m 644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
for u in sparky-stereo-time.service sparky-stereo-time-watch.service sparky-stereo-time-check.service sparky-stereo-time-check.timer; do
	install -m 644 "$HERE/systemd/$u" "$D/usr/lib/systemd/system/"
done
# the package's own messages, word for word, as journal catalogs the engine reads in the person's language
sparky-stereo-problems catalog $PKG "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL27
cat >"$D/etc/chrony/conf.d/sparky-stereo.conf" <<'EOS'
# Sparky Stereo OS: sparky-stereo-time. A machine with a wrong clock (no RTC) cannot check the
# NTS-KE certificate dates, and with authselectmode prefer no plain source corrects it first.
nocerttimecheck 1
EOS
chmod 644 "$D/etc/chrony/conf.d/sparky-stereo.conf"
printf '/etc/chrony/conf.d/sparky-stereo.conf\n' >"$D/DEBIAN/conffiles"
ln -s ../sparky-stereo-time.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-time.service"
ln -s ../sparky-stereo-time-watch.service "$D/usr/lib/systemd/system/multi-user.target.wants/sparky-stereo-time-watch.service"
ln -s ../sparky-stereo-time-check.timer "$D/usr/lib/systemd/system/timers.target.wants/sparky-stereo-time-check.timer"

# The maintainer scripts never hide a failure (Daniel, 2026-11-01). The time servers, the units and the watcher are
# said and kept by problems.py, and the package configures, as debhelper's own service starts do
# (deb-systemd-invoke start ... || true): chrony keeps the sources it had, and sparky-stereo-time --repair does the
# step again. A masked unit is the system's own choice and is said.
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
# postinst script
set -e
P=/usr/lib/sparky-stereo-time/problems.py
if [ "$1" = "configure" ]; then
	# the tool says and keeps what fails (the catalogue, the timezone, the file, chrony)
	/usr/bin/sparky-stereo-time || :
	if [ -d /run/systemd/system ]; then
		python3 $P run units LOCAL45 --repair systemctl daemon-reload -- systemctl daemon-reload || :
		for u in sparky-stereo-time-watch.service:watcher:LOCAL44:restart sparky-stereo-time-check.timer:check-timer:LOCAL42:start; do
			unit=${u%%:*}; rest=${u#*:}; step=${rest%%:*}; rest=${rest#*:}; key=${rest%%:*}; verb=${rest#*:}
			if [ "$(systemctl is-enabled "$unit" 2>/dev/null || :)" = masked ]; then
				python3 $P say LOCAL50 "$unit" "$unit"
			else
				python3 $P run "$step" "$key" -- systemctl "$verb" "$unit" || :
			fi
		done
	fi
fi
exit 0
EOS
cat >"$D/DEBIAN/prerm" <<'EOS'
#!/bin/sh
# prerm script
set -e
P=/usr/lib/sparky-stereo-time/problems.py
if { [ "$1" = "remove" ] || [ "$1" = "upgrade" ]; } && [ -d /run/systemd/system ]; then
	for u in sparky-stereo-time-watch.service sparky-stereo-time-check.timer; do
		# said; the upgrade or the removal goes on (the new postinst starts the watcher again)
		systemctl stop "$u" 2>/dev/null || python3 $P say LOCAL46 "systemctl stop $u" "$?"
	done
fi
exit 0
EOS
# postrm runs after the package's files are gone: its messages are written into it here, from the language files
messages() {
	for l in "$HERE"/lang/*; do
		code=$(basename "$l")
		printf '\t%s)\n\t\tcase $1 in\n' "$code"
		for k in 43 51 52; do
			printf '\t\t%s) f=%s ;;\n' "$k" "$(sed -n "s/^LOCAL$k=\(\".*\"\)\$/\1/p" "$l")"
		done
		printf '\t\tesac ;;\n'
	done
}
{
cat <<'EOS'
#!/bin/sh
# postrm script
set -e
# the messages in the system's language (the package's language files are gone by now)
say() {
	f=
	case $lang in
EOS
messages
cat <<'EOS'
	esac
	k=$1; shift
	# shellcheck disable=SC2059
	printf "sparky-stereo-time: $f\n" "$@" >&2
	if [ "$lang" != en ]; then lang_was=$lang; lang=en; say "$k" "$@"; lang=$lang_was; fi
}
lang=${LANG:-}
case $lang in ""|C|C.*|POSIX) lang=$(sed -n 's/^LANG=//p' /etc/default/locale 2>/dev/null | tr -d '"' | head -n 1) ;; esac
lang=${lang%%.*}
case $lang in
pt_BR|zh_CN|zh_TW) ;;
zh*) lang=zh_CN ;;
*) lang=${lang%%_*}; case $lang in pl|fr|de|ja|ko) ;; *) lang=en ;; esac ;;
esac
failed=0
# a file of ours that cannot be removed would keep chrony on our servers after the package is gone: the removal
# stops (no error unwind, the package stays half-installed and the removal can run again, Debian Policy 6.7)
must() { if "$@"; then :; else rc=$?; say 51 "$*" "$rc"; failed=1; fi; }
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
	must rm -f /etc/chrony/sources.d/sparky-stereo.sources
	# chrony.conf itself is never touched; our generated conf.d snippet goes, chrony restarts once
	changed=0
	if [ -f /etc/chrony/conf.d/sparky-stereo-auth.conf ]; then must rm -f /etc/chrony/conf.d/sparky-stereo-auth.conf; changed=1; fi
	if [ -d /run/systemd/system ]; then
		systemctl daemon-reload || say 52 "systemctl daemon-reload" "$?"
		if [ "$changed" = 1 ]; then
			systemctl try-restart chrony.service || say 43 "systemctl try-restart chrony.service: exit status $?"
		elif systemctl is-active --quiet chrony.service; then
			out=$(chronyc reload sources 2>&1) || say 43 "chronyc reload sources: $out"
		fi
	elif [ "$changed" = 0 ]; then
		# no systemd: a chrony started by hand is told; none running reads chrony.conf when it starts
		out=$(chronyc reload sources 2>&1) || case $out in *"Cannot talk to daemon"*) ;; *) say 43 "chronyc reload sources: $out" ;; esac
	fi
fi
# a problem of a package that is gone cannot be repaired by it (ORDER 350): the engine lets go of them
if [ "$1" = "remove" ] && command -v sparky-stereo-problems >/dev/null; then
	sparky-stereo-problems clear --all sparky-stereo-time || failed=1
fi
if [ "$1" = "purge" ]; then
	must rm -rf /var/lib/sparky-stereo-time
fi
exit $failed
EOS
} >"$D/DEBIAN/postrm"
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm" "$D/DEBIAN/prerm"

cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s):
    Paweł "pavroo" Pijanowski <pavroo@onet.eu>
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: *
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3

Files: usr/bin/sparky-stereo-time
    The timezone-to-country lookup follows sparky-ntp-server (2025)
    Copyright (C) 2025 Daniel Ramos (Capitain Jack)
    License: GPL-3

License:

    This package is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This package is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this package; if not, see <http://www.gnu.org/licenses/>.

On Debian systems, the complete text of the GNU General
Public License can be found in `/usr/share/common-licenses/GPL-3'.
EOS

SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: ca-certificates, chrony, python3, iproute2, systemd, sparky-stereo-problems (>= 0.1.0)
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo time servers
  Sets chrony's time sources from the timezone: the country's official
  service, with NTS where it offers it, or Debian's pool where it has none.
  Countries with two or more NTS servers use authselectmode prefer, so Debian's
  pool is never selected next to them. chrony.conf is not modified.
  A catalogue or timezone that cannot be read, sources that cannot be written,
  a chrony that does not take them and servers that do not answer are said,
  kept by sparky-stereo-problems and shown in the session; the sources in use are never replaced by
  another choice behind the person's back.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
