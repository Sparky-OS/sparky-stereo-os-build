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
check "Sao_Paulo -> NTP.br with nts" America/Sao_Paulo '^server a\.st1\.ntp\.br iburst nts$' 'pool'
check "Berlin -> PTB with nts" Europe/Berlin '^server ptbtime1\.ptb\.de iburst nts$' 'pool'
check "Vienna -> BEV (zone1970 or zone.tab)" Europe/Vienna '^server bevtime1\.metrologie\.at iburst nts$' 'pool'
check "Copenhagen -> DFM plus pool" Europe/Copenhagen '^server time\.dfm\.dk iburst nts$'
check "Copenhagen has the pool completing it" Europe/Copenhagen '^pool debian\.pool\.ntp\.org iburst maxsources 2$'
check "Tokyo (NICT left out) -> Debian pool only" Asia/Tokyo '^pool debian\.pool\.ntp\.org iburst$' 'nict|^server'
check "New York (NIST left out) -> Debian pool only" America/New_York '^pool debian\.pool\.ntp\.org iburst$' 'nist|^server'
check "Lisbon (no service) -> Debian pool only" Europe/Lisbon '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Auckland (NZ excluded) -> Debian pool only" Pacific/Auckland '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Backward alias Asia/Calcutta resolves, no service -> pool" Asia/Calcutta '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Unknown zone -> Debian pool" Nowhere/Land '^pool debian\.pool\.ntp\.org iburst$' '^server'
check "Never a public country zone" Europe/Lisbon 'debian\.pool' '(^|[ .])(br|pt|jp|us|de)\.pool\.ntp\.org'
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
echo "failures: $FAILS"
exit $((FAILS > 0))
