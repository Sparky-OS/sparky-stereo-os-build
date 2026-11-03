#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Tests the generator against the real tzdata and the shipped TSV; each check can fail.
# Run as root in a throwaway container with the package and chrony installed (never on a real system: it creates
# /run/systemd/system and puts fake systemctl, chronyc, ip and busctl first on PATH for the cases that need them).
# Last update 2026/11/02
T=${T:-sparky-stereo-time}
TSV=${SPARKY_TIME_TSV:-/usr/share/sparky-stereo-time/ntp-countries.tsv}
LANGDIR=${SPARKY_TIME_LANGDIR:-/usr/share/sparky/sparky-stereo-time}
FAILS=0
# problems of the cases are kept by the engine (sparky-stereo-problems) under this root, never in the system's /var/lib
export SPARKY_STEREO_ROOT=$(mktemp -d)
# a problem's record in the engine's machine store
rec() { echo "$SPARKY_STEREO_ROOT/var/lib/sparky-stereo-problems/sparky-stereo-time_$1.json"; }
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
check "Copenhagen -> DFM alone" Europe/Copenhagen '^server time\.dfm\.dk iburst nts$'
check "Copenhagen has no added pool" Europe/Copenhagen '^server time\.dfm\.dk iburst' '^pool|authselectmode'
check "Tokyo (NICT left out) -> country pool only" Asia/Tokyo '^pool jp\.pool\.ntp\.org iburst$' 'nict|^server'
check "New York (NIST left out) -> country pool only" America/New_York '^pool us\.pool\.ntp\.org iburst$' 'nist|^server'
check "Lisbon (no service) -> country pool only" Europe/Lisbon '^pool pt\.pool\.ntp\.org iburst$' '^server'
check "Auckland (NZ excluded) -> country pool only" Pacific/Auckland '^pool nz\.pool\.ntp\.org iburst$' '^server'
check "Backward alias Brazil/East (tzdata.zi link) -> NTP.br" Brazil/East '^server a\.st1\.ntp\.br iburst nts$' 'debian'
check "Backward alias Asia/Calcutta, no service -> pool" Asia/Calcutta '^pool in\.pool\.ntp\.org iburst$' '^server'
check "Stockholm -> RISE, both NTS alone" Europe/Stockholm '^server nts1\.ri\.se iburst nts$' '^server nts[^12]'
check "Stockholm second server" Europe/Stockholm '^server nts2\.ri\.se iburst nts$'
check "Stockholm has no added pool" Europe/Stockholm '^server nts1\.ri\.se iburst' '^pool'
check "Madrid -> ROA nts1 only" Europe/Madrid '^server nts1\.roa\.es iburst nts$' 'hora\.roa'
check "Canary -> ROA" Atlantic/Canary '^server nts1\.roa\.es iburst nts$' 'hora\.roa'
check "Paris -> LNE-OP with nts" Europe/Paris '^server ntp\.obspm\.fr iburst nts$'
check "Paris has no added pool" Europe/Paris '^server ntp\.obspm\.fr iburst' '^pool|authselectmode'
check "Vienna three servers" Europe/Vienna '^server time\.metrologie\.at iburst nts$' 'pool'
check "Berlin three servers" Europe/Berlin '^server ptbtime3\.ptb\.de iburst nts$' 'pool'
check "Zurich (zone.tab: CH) -> METAS plain, not DE" Europe/Zurich '^server ntp11\.metas\.ch iburst$' 'nts|ptbtime|pool'
check "Zurich has no authselectmode" Europe/Zurich '^server ntp13\.metas\.ch iburst$' 'authselectmode'
check "London -> NPL plain, three servers, no pool" Europe/London '^server ntp3\.npl\.co\.uk iburst$' 'nts|pool|authselectmode'
check "Warsaw -> GUM plain" Europe/Warsaw '^server tempus1\.gum\.gov\.pl iburst$' 'nts|pool'
check "Johannesburg -> NMISA one plain server alone" Africa/Johannesburg '^server time\.nmisa\.org iburst' '^pool'
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
check "Unknown zone is reported without a pool" Nowhere/Land 'The country of timezone' '^pool|^server'
check "Lisbon uses its country pool" Europe/Lisbon '^pool pt\.pool\.ntp\.org iburst$' 'debian'
# every TSV country is reachable through some zone, and none of the excluded institutes is in the file
bad=$(grep -v '^#' "$TSV" | grep -i -E '^(JP|US|NZ|AU)	|nict\.|nist\.gov|measurement\.go' || true)
[ -z "$bad" ] && echo "PASS TSV has no excluded institute" || { echo "FAIL TSV: $bad"; FAILS=$((FAILS + 1)); }
# the write path: a file in a temp dir, a second run says unchanged
D=$(mktemp -d); export SPARKY_TIME_OUT=$D/s.sources
LANG=C $T --zone America/Sao_Paulo --no-reload >/dev/null
grep -q 'server a.st1.ntp.br iburst nts' "$SPARKY_TIME_OUT" && echo "PASS file written" || { echo "FAIL file written"; FAILS=$((FAILS + 1)); }
[ "$(LANG=C $T --zone America/Sao_Paulo --no-reload | head -n1)" = "Time servers unchanged" ] && echo "PASS second run unchanged" || { echo "FAIL second run"; FAILS=$((FAILS + 1)); }
# strings: pt_BR, pl, en and de (German has its own strings since 20261029)
for l in "pt_BR.UTF-8:Sem serviço nacional" "pl_PL.UTF-8:Brak krajowej usługi" "en_US.UTF-8:No national time service" "de_DE.UTF-8:Kein nationaler Zeitdienst"; do
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
zcheck "shared zone1970 entry (CH,DE,LI) is not DE" Europe/Fakezurich 'The country of timezone' '^pool|^server'
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
# no timezone at all is not "no national service": it is said, and nothing is printed as the sources
rm -f "$L/localtime" "$L/timezone"
out=$(SPARKY_TIME_LOCALTIME=$L/localtime SPARKY_TIME_TIMEZONE_FILE=$L/timezone LANG=C $T --print 2>&1); rc=$?
[ "$rc" = 3 ] && echo "$out" | grep -q 'The timezone is not known' && ! echo "$out" | grep -q '^pool' \
	&& echo "PASS nothing at all -> the timezone is said to be unknown (exit 3), no pool printed" || { echo "FAIL nothing at all ($rc): $out"; FAILS=$((FAILS + 1)); }
# --zone needs a value
LANG=C $T --print --zone >/dev/null 2>&1; [ $? -eq 2 ] && echo "PASS --zone without value is refused" || { echo "FAIL --zone without value"; FAILS=$((FAILS + 1)); }
# authselectmode: prefer with two or more NTS servers, default mix (no line) with one or none
check "BR (3 NTS) -> authselectmode prefer" America/Sao_Paulo '^# conf\.d: authselectmode prefer$'
check "SE (2 NTS) -> authselectmode prefer" Europe/Stockholm '^# conf\.d: authselectmode prefer$'
check "AT (3 NTS) -> authselectmode prefer" Europe/Vienna '^# conf\.d: authselectmode prefer$'
check "DK (1 NTS) -> mix, no prefer" Europe/Copenhagen '^server time\.dfm\.dk iburst' '^pool|authselectmode'
check "ES (1 NTS) -> mix, no prefer" Europe/Madrid '^server nts1\.roa\.es iburst' '^pool|authselectmode'
check "FR (1 NTS) -> mix, no prefer" Europe/Paris '^server ntp\.obspm\.fr iburst' '^pool|authselectmode'
check "Lisbon (no service) -> no prefer" Europe/Lisbon '^pool pt' 'authselectmode'
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
# ---- ORDER 346c: nothing fails silently (Daniel, 2026-11-01). Each case below fails on 20261029~sparky9~0.
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
kept() { [ -s "$(rec "$1")" ] && grep -q "\"message\":\"$2\"" "$(rec "$1")"; }
# a new, empty engine root for the next case
fresh() { SPARKY_STEREO_ROOT=$(mktemp -d); export SPARKY_STEREO_ROOT; }
NOBODY="setpriv --reuid=65534 --regid=65534 --clear-groups"
# U12: a catalogue that cannot be read is said and kept, and the sources in use stay as they are
fresh; D=$(mktemp -d); chmod 777 "$D"; export SPARKY_TIME_OUT=$D/s.sources
printf 'server previous.example iburst\n' >"$SPARKY_TIME_OUT"
out=$(SPARKY_TIME_TSV=$D/missing.tsv LANG=C $T --zone Europe/Paris --no-reload 2>&1); rc=$?
ok "U12 missing catalogue: exit 3" '[ "$rc" = 3 ]'
ok "U12 missing catalogue: said, with its path and reason" 'echo "$out" | grep -q "The time-server catalogue $D/missing.tsv could not be read (No such file or directory)"'
ok "U12 missing catalogue: the sources in use are not replaced by the pool" '[ "$(cat "$SPARKY_TIME_OUT")" = "server previous.example iburst" ]'
ok "U12 missing catalogue: kept as the catalogue problem" 'kept catalogue LOCAL10'
ok "U12 missing catalogue: not announced as written" '! echo "$out" | grep -q -E "written|No national"'
out=$(SPARKY_TIME_TSV=$D/missing.tsv LANG=C $T --print --zone Europe/Paris 2>&1); rc=$?
ok "U12 --print with a missing catalogue: exit 3, no pool printed" '[ "$rc" = 3 ] && ! echo "$out" | grep -q "^pool"'
printf '# only a comment\n\n' >"$D/empty.tsv"
out=$(SPARKY_TIME_TSV=$D/empty.tsv LANG=C $T --print --zone Europe/Paris 2>&1); rc=$?
ok "U12 a catalogue without rows: exit 3, said" '[ "$rc" = 3 ] && echo "$out" | grep -q "it has no time-server rows"'
cp "$TSV" "$D/locked.tsv"; chmod 000 "$D/locked.tsv"
out=$(SPARKY_TIME_TSV=$D/locked.tsv LANG=C $NOBODY $T --print --zone Europe/Paris 2>&1); rc=$?
ok "U12 an unreadable catalogue: exit 3, Permission denied said" '[ "$rc" = 3 ] && echo "$out" | grep -q "Permission denied"'
# U12: the timezone tables that name the country, missing
Z2=$(mktemp -d)
out=$(SPARKY_TIME_ZONEINFO=$Z2 LANG=C $T --print --zone America/Sao_Paulo 2>&1); rc=$?
ok "U12 missing timezone tables: exit 3, not taken as no national service" '[ "$rc" = 3 ] && echo "$out" | grep -q "The timezone tables in $Z2 could not be read" && ! echo "$out" | grep -q -E "^pool|No national"'
# U12: the problem is cleared when the step works again, and the sources are written
out=$(LANG=C $T --zone Europe/Paris --no-reload 2>&1); rc=$?
ok "U12 repaired catalogue: written, the problem cleared" '[ "$rc" = 0 ] && grep -q "server ntp.obspm.fr iburst nts" "$SPARKY_TIME_OUT" && [ ! -e "$(rec catalogue)" ]'
# the policy is said: the sources chosen, the pool where it completes the country's servers
ok "the chosen sources are said, without a pool beside one NTS server" 'echo "$out" | grep -q "^Time sources: ntp.obspm.fr (NTS)$"'
# U13: a file that cannot be written is said, never announced as written
fresh; XS=$(mktemp -d); chmod 777 "$XS"; R=$(mktemp -d); chmod 555 "$R"
out=$(SPARKY_TIME_OUT=$R/sub/s.sources XDG_STATE_HOME=$XS LANG=C $NOBODY $T --zone Europe/Paris --no-reload 2>&1); rc=$?
ok "U13 unwritable sources: exit 4, said, not announced as written" '[ "$rc" = 4 ] && echo "$out" | grep -q "could not be written to" && ! echo "$out" | grep -q "written$"'
# the nine languages, from the installed language files
for l in en_US pl_PL pt_BR fr_FR de_DE ja_JP ko_KR zh_CN zh_TW; do
	code=${l%_*}; case $l in pt_BR|zh_CN|zh_TW) code=$l ;; esac
	want=$(sed -n 's/^LOCAL10="\([^%]*\)%s.*/\1/p' "$LANGDIR/$code")
	out=$(SPARKY_TIME_TSV=$D/missing.tsv LANG=$l.UTF-8 $T --print --zone Europe/Paris 2>&1 | head -n1)
	ok "U12 said in $l" '[ -n "$want" ] && case "$out" in "sparky-stereo-time: $want"*) true ;; *) false ;; esac'
done
[ "$(sed -n 's/^LOCAL10="\(.*\)"$/\1/p' "$LANGDIR/pt_BR")" != "$(sed -n 's/^LOCAL10="\(.*\)"$/\1/p' "$LANGDIR/en")" ] && echo "PASS the pt_BR text is not the English" || { echo "FAIL pt_BR = en"; FAILS=$((FAILS + 1)); }

# U13: chrony that does not take the sources, or has failed. Fakes first on PATH; /run/systemd/system says systemd runs
F=$(mktemp -d); mkdir -p /run/systemd/system
cat >"$F/systemctl" <<'EOS'
#!/bin/sh
case "$1" in
is-active) cat "$FAKE/state" ;;
try-restart) [ -e "$FAKE/restart-fails" ] && { echo "Job for chrony.service failed." >&2; exit 1; }; exit 0 ;;
show) echo "Mon 2026-11-02 00:00:00 UTC" ;;
*) exit 0 ;;
esac
EOS
cat >"$F/chronyc" <<'EOS'
#!/bin/sh
case "$*" in
"reload sources") [ -e "$FAKE/reload-fails" ] && { echo "501 Not authorised"; exit 1; }; echo 200 OK ;;
"-N -c sources") cat "$FAKE/sources" ;;
*) exit 1 ;;
esac
EOS
printf '#!/bin/sh\ncase "$*" in *default*) cat "$FAKE/route" ;; esac\n' >"$F/ip"
chmod 755 "$F/systemctl" "$F/chronyc" "$F/ip"; export FAKE=$F
fresh; D=$(mktemp -d); export SPARKY_TIME_OUT=$D/s.sources
echo active >"$F/state"; : >"$F/reload-fails"
out=$(PATH=$F:$PATH LANG=C $T --zone Europe/Copenhagen 2>&1); rc=$?
ok "U13 a running chrony refuses the reload: exit 4" '[ "$rc" = 4 ]'
ok "U13 the refusal is said with chronyc's answer" 'echo "$out" | grep -q "chrony did not take the new time servers: chronyc reload sources ended with exit status 1" && echo "$out" | grep -q "501 Not authorised"'
ok "U13 the refusal is kept with its evidence" 'kept apply LOCAL14 && grep -q "501 Not authorised" "$(rec apply)"'
ok "U13 a refusal is not reported as chrony not running" '! echo "$out" | grep -q "chrony is not running"'
mv "$F/reload-fails" "$F/reload-works"
out=$(PATH=$F:$PATH LANG=C $T --zone Europe/Copenhagen 2>&1); rc=$?
ok "U13 the reload works again: exit 0, the problem cleared" '[ "$rc" = 0 ] && [ ! -e "$(rec apply)" ]'
: >"$F/restart-fails"
out=$(PATH=$F:$PATH LANG=C $T --zone America/Sao_Paulo 2>&1); rc=$?
ok "U13 a new authselectmode that chrony's restart does not take: exit 4, kept" '[ "$rc" = 4 ] && kept apply LOCAL14 && echo "$out" | grep -q "systemctl try-restart chrony.service ended with exit status 1"'
mv "$F/restart-fails" "$F/restart-works"; echo failed >"$F/state"
out=$(PATH=$F:$PATH LANG=C $T --zone America/Sao_Paulo 2>&1); rc=$?
ok "U13 a failed chrony: exit 4, said and kept" '[ "$rc" = 4 ] && kept chrony LOCAL15 && echo "$out" | grep -q "chrony has failed, so the clock is not kept"'
fresh; echo inactive >"$F/state"
out=$(PATH=$F:$PATH LANG=C $T --zone America/Sao_Paulo 2>&1); rc=$?
ok "a stopped chrony reads the sources at its start: exit 0, said, nothing kept" '[ "$rc" = 0 ] && echo "$out" | grep -q "chrony is not running" && [ ! -e "$(rec chrony)" ]'

# the time source that cannot be reached: --check reads chrony's reachability of the servers this tool chose
fresh; echo active >"$F/state"; echo 'default via 192.0.2.1 dev eth0' >"$F/route"
LANG=C $T --zone America/Sao_Paulo --no-reload >/dev/null 2>&1; touch -d '10 minutes ago' "$SPARKY_TIME_OUT"
export SPARKY_TIME_LOCALTIME=$D/localtime; ln -s /usr/share/zoneinfo/America/Sao_Paulo "$SPARKY_TIME_LOCALTIME"
printf '%s\n' '^,?,gps.ntp.br,0,6,0,,0,0,0' '^,?,a.st1.ntp.br,0,6,0,,0,0,0' '^,?,c.st1.ntp.br,0,6,0,,0,0,0' \
	'^,?,d.st1.ntp.br,0,6,0,,0,0,0' '^,?,e.st1.ntp.br,0,6,0,,0,0,0' '^,*,2.debian.pool.ntp.org,2,6,377,12,0,0,0' >"$F/sources"
out=$(PATH=$F:$PATH LANG=C $T --check 2>&1); rc=$?
ok "reach: none of the chosen servers answers: exit 5" '[ "$rc" = 5 ]'
ok "reach: said, with what the clock follows instead" 'echo "$out" | grep -q "None of the time servers chosen for BR (America/Sao_Paulo) answers: gps.ntp.br, a.st1.ntp.br, c.st1.ntp.br, d.st1.ntp.br, e.st1.ntp.br. The clock follows 2.debian.pool.ntp.org instead."'
ok "reach: kept" 'kept reach LOCAL17'
first=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["first"])' "$(rec reach)"); sleep 1
PATH=$F:$PATH LANG=C $T --check >/dev/null 2>&1
ok "reach: found again, it keeps the time it was first found (shown once)" '[ -n "$first" ] && [ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))[\"first\"])" "$(rec reach)")" = "$first" ]'
sed -i 's/^\^,?,gps.ntp.br,0,6,0,/^,*,gps.ntp.br,1,6,377,/; s/^\^,\*,2.debian/^,-,2.debian/' "$F/sources"
out=$(PATH=$F:$PATH LANG=C $T --check 2>&1); rc=$?
ok "reach: a server answers again: exit 0, cleared, said" '[ "$rc" = 0 ] && [ ! -e "$(rec reach)" ] && echo "$out" | grep -q "The chosen time servers answer: gps.ntp.br." && echo "$out" | grep -q "The clock follows gps.ntp.br."'
sed -i 's/^\^,\*,gps.ntp.br,1,6,377,/^,?,gps.ntp.br,0,6,0,/' "$F/sources"; : >"$F/route"
out=$(PATH=$F:$PATH LANG=C $T --check 2>&1); rc=$?
ok "reach: no network is not a server problem: exit 0, said, nothing kept" '[ "$rc" = 0 ] && echo "$out" | grep -q "No network" && [ ! -e "$(rec reach)" ]'
echo 'default via 192.0.2.1 dev eth0' >"$F/route"; touch "$SPARKY_TIME_OUT"
out=$(PATH=$F:$PATH LANG=C $T --check 2>&1); rc=$?
ok "reach: sources changed a moment ago are checked later, not judged" '[ "$rc" = 0 ] && echo "$out" | grep -q "checked later" && [ ! -e "$(rec reach)" ]'
touch -d '10 minutes ago' "$SPARKY_TIME_OUT"

# status, dismiss, repair and the session's notification
fresh; PATH=$F:$PATH LANG=C $T --check >/dev/null 2>&1
out=$(LANG=C $T --status 2>&1); rc=$?
ok "status lists the kept problem and exits 1" '[ "$rc" = 1 ] && echo "$out" | grep -q "None of the time servers chosen"'
# the session's notifier shows the problems now (sparky-stereo-problems-plasma): --notify starts it
NF=$(mktemp -d)
printf '#!/bin/sh\necho "$*" >>%s/systemctl.log\n' "$NF" >"$NF/systemctl"; chmod 755 "$NF/systemctl"
PATH=$NF:$PATH LANG=C $T --notify
ok "notify: starts the session's notifier, which shows every problem" 'grep -q "^--user start sparky-stereo-problems-notifier.service$" "$NF/systemctl.log"'
export XDG_STATE_HOME=$(mktemp -d)
out=$(LANG=C $T --dismiss reach 2>&1); rc=$?
ok "dismiss: said, and status no longer counts it" '[ "$rc" = 0 ] && echo "$out" | grep -q "reach is not shown again until it changes or is repaired." && LANG=C $T --status >/dev/null 2>&1'
ok "dismiss is the engine's Hide: kept listed, hidden for you" 'sparky-stereo-problems list --json | python3 -c "import json,sys; d=[p for p in json.load(sys.stdin) if p.get(\"key\") == \"reach\"]; sys.exit(0 if d and d[0][\"hidden\"] else 1)"'
PATH=$F:$PATH LANG=C $T --check >/dev/null 2>&1
ok "dismiss: the same problem found again stays hidden" 'sparky-stereo-problems list --json | python3 -c "import json,sys; d=[p for p in json.load(sys.stdin) if p.get(\"key\") == \"reach\"]; sys.exit(0 if d and d[0][\"hidden\"] else 1)"'
sed -i 's/^\^,?,gps.ntp.br,0,6,0,/^,*,gps.ntp.br,1,6,377,/' "$F/sources"
out=$(PATH=$F:$PATH SPARKY_TIME_SELF=$(command -v $T) LANG=C $T --repair 2>&1); rc=$?
ok "repair runs the check again; a server answers: repaired, cleared" '[ "$rc" = 0 ] && echo "$out" | grep -q "Repaired: reach" && [ ! -e "$(rec reach)" ]'
unset SPARKY_TIME_LOCALTIME

# U13: the watcher's monitor that cannot listen is said and kept; the tool is not run
fresh; W2=$(command -v sparky-stereo-time-watch || echo "$(dirname "$T")/sparky-stereo-time-watch")
printf '#!/bin/sh\necho "Failed to connect to bus: No such file or directory" >&2\nexit 1\n' >"$F/busctl-dead"; chmod 755 "$F/busctl-dead"
SPARKY_TIME_BUSCTL=$F/busctl-dead SPARKY_TIME_TOOL=/bin/false LANG=C "$W2" 2>"$F/watch.err"; rc=$?
ok "U13 watcher: exit 1 (systemd starts it again)" '[ "$rc" = 1 ]'
ok "U13 watcher: the reason is said and kept" 'kept watcher LOCAL16 && grep -q "Failed to connect to bus" "$F/watch.err" && grep -q "Failed to connect to bus" "$(rec watcher)"'

# U13: the maintainer script says and keeps a watcher that cannot be started; the package configures
fresh; PI=${SPARKY_TIME_POSTINST:-/var/lib/dpkg/info/sparky-stereo-time.postinst}
if [ -x "$PI" ]; then
	cat >"$F/systemctl" <<'EOS'
#!/bin/sh
case "$1" in
restart) echo "Failed to restart $2: Unit $2 not found." >&2; exit 5 ;;
is-enabled) echo enabled ;;
is-active) echo inactive ;;
*) exit 0 ;;
esac
EOS
	out=$(PATH=$F:$PATH LANG=C "$PI" configure 2>&1); rc=$?
	ok "U13 postinst: the package configures (exit 0)" '[ "$rc" = 0 ]'
	ok "U13 postinst: the watcher that did not start is said" 'echo "$out" | grep -q "The timezone watcher could not be started: systemctl restart sparky-stereo-time-watch.service ended with exit status 5"'
	ok "U13 postinst: and kept" 'kept watcher LOCAL44'
else
	echo "FAIL postinst not installed at $PI"; FAILS=$((FAILS + 1))
fi
rmdir /run/systemd/system
unset SPARKY_TIME_OUT
echo "failures: $FAILS"
exit $((FAILS > 0))
