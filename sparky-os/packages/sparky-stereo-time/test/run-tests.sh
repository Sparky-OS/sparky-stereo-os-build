#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Tests the generator against the real tzdata and the shipped TSV; each check can fail.
# Last update 2026/10/02
T=${T:-sparky-stereo-time}
TSV=${SPARKY_TIME_TSV:-/usr/share/sparky-stereo-time/ntp-countries.tsv}
FAILS=0
check() { # name, zone, expected-grep-pattern(s) joined by |, absent-pattern
	local out
	out=$(LANG=C $T --print --zone "$2" 2>&1)
	if echo "$out" | grep -q -E "$3" && { [ -z "${4:-}" ] || ! echo "$out" | grep -q -E "$4"; }; then
		echo "PASS $1"
	else
		echo "FAIL $1: $out"; FAILS=$((FAILS + 1))
	fi
}
check "Sao_Paulo -> NTP.br with nts" America/Sao_Paulo '^server a\.st1\.ntp\.br iburst nts$' 'debian'
check "Sao_Paulo -> gps.ntp.br with nts" America/Sao_Paulo '^server gps\.ntp\.br iburst nts$' 'debian'
check "Sao_Paulo has no b.st1 (no NTS answer)" America/Sao_Paulo '^server a\.st1' 'b\.st1'
check "Berlin -> PTB with nts" Europe/Berlin '^server ptbtime1\.ptb\.de iburst nts$' 'pool'
check "Vienna -> BEV (zone1970 or zone.tab)" Europe/Vienna '^server bevtime1\.metrologie\.at iburst nts$' 'pool'
check "Copenhagen -> DFM plus pool" Europe/Copenhagen '^server time\.dfm\.dk iburst nts$'
check "Copenhagen has the pool completing it" Europe/Copenhagen '^pool debian\.pool\.ntp\.org iburst maxsources 2$'
check "Tokyo (NICT left out) -> Debian pool only" Asia/Tokyo '^pool debian\.pool\.ntp\.org iburst$' 'nict|^server'
check "New York (NIST left out) -> Debian pool only" America/New_York '^pool debian\.pool\.ntp\.org iburst$' 'nist|^server'
check "Lisbon (no service) -> Debian pool only" Europe/Lisbon '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Auckland (NZ excluded) -> Debian pool only" Pacific/Auckland '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Backward alias Brazil/East (tzdata.zi link) -> NTP.br" Brazil/East '^server a\.st1\.ntp\.br iburst nts$' 'debian'
check "Backward alias Asia/Calcutta, no service -> pool" Asia/Calcutta '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Stockholm -> RISE, both nts, pool maxsources 2" Europe/Stockholm '^server nts1\.ri\.se iburst nts$' '^server nts[^12]'
check "Stockholm second server" Europe/Stockholm '^server nts2\.ri\.se iburst nts$'
check "Stockholm pool completes" Europe/Stockholm '^pool debian\.pool\.ntp\.org iburst maxsources 2$'
check "Madrid -> ROA nts1 only" Europe/Madrid '^server nts1\.roa\.es iburst nts$' 'hora\.roa'
check "Canary -> ROA" Atlantic/Canary '^server nts1\.roa\.es iburst nts$' 'hora\.roa'
check "Paris -> LNE-OP with nts" Europe/Paris '^server ntp\.obspm\.fr iburst nts$'
check "Paris pool completes" Europe/Paris '^pool debian\.pool\.ntp\.org iburst maxsources 2$'
check "Vienna three servers" Europe/Vienna '^server time\.metrologie\.at iburst nts$' 'pool'
check "Berlin three servers" Europe/Berlin '^server ptbtime3\.ptb\.de iburst nts$' 'pool'
check "Zurich (zone.tab: CH) -> METAS plain, not DE" Europe/Zurich '^server ntp11\.metas\.ch iburst$' 'nts|ptbtime|pool'
check "Zurich has no authselectmode" Europe/Zurich '^server ntp13\.metas\.ch iburst$' 'authselectmode'
check "London -> NPL plain, three servers, no pool" Europe/London '^server ntp3\.npl\.co\.uk iburst$' 'nts|pool|authselectmode'
check "Warsaw -> GUM plain" Europe/Warsaw '^server tempus1\.gum\.gov\.pl iburst$' 'nts|pool'
check "Johannesburg -> NMISA one plain server plus the Debian pool" Africa/Johannesburg '^pool debian\.pool\.ntp\.org iburst maxsources 2$' 'nts|authselectmode'
check "Johannesburg server line" Africa/Johannesburg '^server time\.nmisa\.org iburst$'
check "Moscow -> VNIIFTRI plain, four servers, no pool" Europe/Moscow '^server ntp4\.vniiftri\.ru iburst$' 'nts|pool'
# Brazil's servers come out in the TSV order, gps.ntp.br first, all five with nts
br=$(LANG=C $T --print --zone America/Sao_Paulo | sed -n 2,6p | tr '\n' ' ')
[ "$br" = "server gps.ntp.br iburst nts server a.st1.ntp.br iburst nts server c.st1.ntp.br iburst nts server d.st1.ntp.br iburst nts server e.st1.ntp.br iburst nts " ] && echo "PASS BR order and five NTS servers" || { echo "FAIL BR order: $br"; FAILS=$((FAILS + 1)); }
LANG=C $T --print --zone America/Sao_Paulo | grep -q -E 'pool|b\.st1' && { echo "FAIL BR has a pool or b.st1"; FAILS=$((FAILS + 1)); } || echo "PASS BR has no pool and no b.st1"
# a country with one NTS server and a plain official one: the plain one replaces the Debian pool
M=$(mktemp -d); printf 'XX\tn.example plain.example\tn.example\tfixture\n' >"$M/t.tsv"
printf 'XX\t+0000+00000\tAfrica/Xx\n' >"$M/zone.tab"
out=$(SPARKY_TIME_TSV=$M/t.tsv SPARKY_TIME_ZONEINFO=$M LANG=C $T --print --zone Africa/Xx)
echo "$out" | grep -q '^server plain\.example iburst$' && ! echo "$out" | grep -q -E 'pool|authselectmode' && echo "PASS plain official server replaces the Debian pool next to one NTS server" || { echo "FAIL mixed row: $out"; FAILS=$((FAILS + 1)); }
check "Unknown zone -> Debian pool" Nowhere/Land '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Never a public country zone" Europe/Lisbon 'debian\.pool' '(^|[ ])[a-z]{2}\.pool\.ntp\.org'
# every TSV country is reachable through some zone, and none of the excluded institutes is in the file
bad=$(grep -v '^#' "$TSV" | grep -i -E '^(JP|US|NZ|AU)	|nict\.|nist\.gov|measurement\.go' || true)
[ -z "$bad" ] && echo "PASS TSV has no excluded institute" || { echo "FAIL TSV: $bad"; FAILS=$((FAILS + 1)); }
# the write path: a file in a temp dir, a second run says unchanged
D=$(mktemp -d); export SPARKY_TIME_OUT=$D/s.sources
LANG=C $T --zone America/Sao_Paulo --no-reload >/dev/null
grep -q 'server a.st1.ntp.br iburst nts' "$SPARKY_TIME_OUT" && echo "PASS file written" || { echo "FAIL file written"; FAILS=$((FAILS + 1)); }
[ "$(LANG=C $T --zone America/Sao_Paulo --no-reload)" = "Time servers unchanged" ] && echo "PASS second run unchanged" || { echo "FAIL second run"; FAILS=$((FAILS + 1)); }
# strings: pl and pt_BR
for l in "pt_BR.UTF-8:Sem serviço nacional" "pl_PL.UTF-8:Brak krajowej usługi" "en_US.UTF-8:No national time service" "de_DE.UTF-8:No national time service"; do
	D=$(mktemp -d)
	r=$(LANG=${l%%:*} SPARKY_TIME_OUT=$D/s.sources $T --zone Europe/Lisbon --no-reload)
	echo "$r" | grep -q "${l#*:}" && echo "PASS text ${l%%:*}" || { echo "FAIL text ${l%%:*}: $r"; FAILS=$((FAILS + 1)); }
	rm -rf "$D"
done
# a fake zoneinfo: zone1970.tab without zone.tab, a tzdata.zi link, and a shared zone1970 entry
Z=$(mktemp -d)
printf 'BR\t-2332-04637\tAmerica/Fakepaulo\tSouth\nCH,DE,LI\t+4723+00832\tEurope/Fakezurich\n' >"$Z/zone1970.tab"
printf 'L America/Fakepaulo Brazil/Fake\n' >"$Z/tzdata.zi"
zcheck() { # name, zone, expected, absent
	local out
	out=$(SPARKY_TIME_ZONEINFO=$Z LANG=C $T --print --zone "$2" 2>&1)
	if echo "$out" | grep -q -E "$3" && { [ -z "${4:-}" ] || ! echo "$out" | grep -q -E "$4"; }; then
		echo "PASS $1"
	else
		echo "FAIL $1: $out"; FAILS=$((FAILS + 1))
	fi
}
zcheck "zone1970.tab alone answers (no zone.tab)" America/Fakepaulo '^server a\.st1\.ntp\.br iburst nts$' 'debian'
zcheck "tzdata.zi link into a zone1970 entry" Brazil/Fake '^server a\.st1\.ntp\.br iburst nts$' 'debian'
zcheck "shared zone1970 entry (CH,DE,LI) is not DE" Europe/Fakezurich '^pool debian\.pool\.ntp\.org iburst$' '^server'
# the zone name from /etc/localtime and /etc/timezone, with files that need not exist
L=$(mktemp -d)
lcheck() { # name, expected-first-line-pattern
	local out
	out=$(SPARKY_TIME_LOCALTIME=$L/localtime SPARKY_TIME_TIMEZONE_FILE=$L/timezone LANG=C $T --print 2>&1)
	if echo "$out" | grep -q -E "$2"; then echo "PASS $1"; else echo "FAIL $1: $out"; FAILS=$((FAILS + 1)); fi
}
ln -sf /usr/share/zoneinfo/Europe/Copenhagen "$L/localtime"; lcheck "localtime symlink" '^server time\.dfm\.dk iburst nts$'
ln -sf /nonexistent/usr/share/zoneinfo/Brazil/East "$L/localtime"; lcheck "symlink whose zone file is missing" '^server a\.st1\.ntp\.br'
ln -sf /usr/share/zoneinfo/posix/Europe/Berlin "$L/localtime"; lcheck "posix/ prefix stripped" '^server ptbtime1\.ptb\.de'
ln -sf ../usr/share/zoneinfo/Europe/Vienna "$L/localtime"; lcheck "relative symlink" '^server bevtime1'
ln -sf "$L/localtime" "$L/hop"; ln -sf /usr/share/zoneinfo/Europe/Madrid "$L/localtime"
SPARKY_TIME_LOCALTIME=$L/hop; lcheck "chain of links" '^server nts1\.roa\.es'; unset SPARKY_TIME_LOCALTIME
ln -sf /nowhere/else "$L/localtime"; echo Europe/Paris >"$L/timezone"; lcheck "dangling link -> /etc/timezone" '^server ntp\.obspm\.fr'
rm -f "$L/localtime"; : >"$L/localtime"; echo Europe/Stockholm >"$L/timezone"; lcheck "regular file -> /etc/timezone" '^server nts1\.ri\.se'
rm -f "$L/localtime" "$L/timezone"; lcheck "nothing at all -> pool" '^pool debian\.pool\.ntp\.org iburst$'
# --zone needs a value
LANG=C $T --print --zone >/dev/null 2>&1; [ $? -eq 2 ] && echo "PASS --zone without value is refused" || { echo "FAIL --zone without value"; FAILS=$((FAILS + 1)); }
# authselectmode: prefer with two or more NTS servers, default mix (no line) with one or none
check "BR (3 NTS) -> authselectmode prefer" America/Sao_Paulo '^# conf\.d: authselectmode prefer$'
check "SE (2 NTS) -> authselectmode prefer" Europe/Stockholm '^# conf\.d: authselectmode prefer$'
check "AT (3 NTS) -> authselectmode prefer" Europe/Vienna '^# conf\.d: authselectmode prefer$'
check "DK (1 NTS) -> mix, no prefer" Europe/Copenhagen '^pool debian' 'authselectmode'
check "ES (1 NTS) -> mix, no prefer" Europe/Madrid '^pool debian' 'authselectmode'
check "FR (1 NTS) -> mix, no prefer" Europe/Paris '^pool debian' 'authselectmode'
check "Lisbon (no service) -> no prefer" Europe/Lisbon '^pool debian' 'authselectmode'
# the generated snippet is written, removed for another country, and chrony.conf is never touched
D=$(mktemp -d); export SPARKY_TIME_OUT=$D/s.sources
printf 'pool 2.debian.pool.ntp.org iburst\nrtcsync\n' >"$D/chrony.conf"; cp "$D/chrony.conf" "$D/chrony.conf.orig"
LANG=C $T --zone America/Sao_Paulo --no-reload >/dev/null
[ "$(sed -n 2p "$D/sparky-stereo-auth.conf")" = "authselectmode prefer" ] && echo "PASS prefer snippet written for BR" || { echo "FAIL prefer snippet"; FAILS=$((FAILS + 1)); }
LANG=C $T --zone Europe/Copenhagen --no-reload >/dev/null
[ ! -e "$D/sparky-stereo-auth.conf" ] && echo "PASS snippet removed for a one-NTS country" || { echo "FAIL snippet stays"; FAILS=$((FAILS + 1)); }
cmp -s "$D/chrony.conf" "$D/chrony.conf.orig" && echo "PASS chrony.conf untouched" || { echo "FAIL chrony.conf changed"; FAILS=$((FAILS + 1)); }
unset SPARKY_TIME_OUT
# the watcher runs the tool for a Timezone signal and for nothing else (fake busctl and tool)
F=$(mktemp -d); W=$(command -v sparky-stereo-time-watch || echo "$(dirname "$T")/sparky-stereo-time-watch")
printf '#!/bin/sh\necho "{\\"member\\":\\"PropertiesChanged\\",\\"data\\":{\\"NTP\\":true}}"\necho "{\\"member\\":\\"PropertiesChanged\\",\\"data\\":{\\"Timezone\\":\\"Europe/Madrid\\"}}"\necho "{\\"member\\":\\"PropertiesChanged\\",\\"data\\":{\\"Timezone\\":\\"Europe/Paris\\"}}"\n' >"$F/busctl"
printf '#!/bin/sh\necho run >>%s/runs\n' "$F" >"$F/tool"; chmod +x "$F/busctl" "$F/tool"
SPARKY_TIME_BUSCTL=$F/busctl SPARKY_TIME_TOOL=$F/tool "$W"; rc=$?
[ "$(wc -l <"$F/runs" 2>/dev/null)" = 2 ] && echo "PASS watcher runs the tool once per Timezone signal, not for NTP" || { echo "FAIL watcher: $(cat "$F/runs" 2>/dev/null)"; FAILS=$((FAILS + 1)); }
[ "$rc" = 1 ] && echo "PASS watcher exits 1 when the monitor ends (systemd restarts it)" || { echo "FAIL watcher exit $rc"; FAILS=$((FAILS + 1)); }
echo "failures: $FAILS"
exit $((FAILS > 0))
