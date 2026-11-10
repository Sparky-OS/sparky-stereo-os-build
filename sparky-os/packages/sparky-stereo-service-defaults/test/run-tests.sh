#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Tests the installed drop-ins and sparky-stereo-service-defaults with fakes for ip, systemctl and journalctl; each
# check can fail. Run as root in a throwaway container with the package installed (never on a real system: the cases
# put fake programs first on PATH). Each ORDER 346c case fails on 0.1.2+lc1.
# Last update 2026/11/02
FAILS=0
SD=${SD:-/usr/lib/systemd/system}
LANGDIR=${SPARKY_SERVICE_DEFAULTS_LANGDIR:-/usr/share/sparky/sparky-stereo-service-defaults}
T=${T:-sparky-stereo-service-defaults}
ok() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; FAILS=$((FAILS + 1)); fi; }
# the problems are kept by the engine (sparky-stereo-problems, ORDER 350) under a root of the case's own
fresh() { SPARKY_STEREO_ROOT=$(mktemp -d); export SPARKY_STEREO_ROOT; }
rec() { echo "$SPARKY_STEREO_ROOT/var/lib/sparky-stereo-problems/sparky-stereo-service-defaults_$1.json"; }
kept() { [ -s "$(rec "$1")" ] && grep -q "\"message\":\"$2\"" "$(rec "$1")"; }
# the value of one directive of a drop-in, all of them when it repeats
directive() { sed -n "s/^$2=//p" "$SD/$1/sparky-stereo.conf" 2>/dev/null; }
F=$(mktemp -d); export FAKE=$F
cat >"$F/ip" <<'EOS'
#!/bin/sh
[ -e "$FAKE/ip-fails" ] && { echo "Cannot open netlink socket: Address family not supported by protocol" >&2; exit 2; }
cat "$FAKE/addresses" 2>/dev/null
EOS
cat >"$F/systemctl" <<'EOS'
#!/bin/sh
[ "$1" = --no-block ] && shift
case "$1" in
show) cat "$FAKE/show" ;;
is-enabled) cat "$FAKE/enabled"; [ "$(cat "$FAKE/enabled")" = enabled ] ;;
restart) echo "$*" >>"$FAKE/restarted"; [ ! -e "$FAKE/restart-fails" ] ;;
*) exit 0 ;;
esac
EOS
cat >"$F/journalctl" <<'EOS'
#!/bin/sh
echo "$*" >>"$FAKE/journal-args"
cat "$FAKE/journal"
EOS
chmod 755 "$F/ip" "$F/systemctl" "$F/journalctl"
export SPARKY_SERVICE_DEFAULTS_IP=$F/ip SPARKY_SERVICE_DEFAULTS_SYSTEMCTL=$F/systemctl SPARKY_SERVICE_DEFAULTS_JOURNALCTL=$F/journalctl

# every drop-in of a service this package sets says its failure: OnFailure names the handler
for u in snmptt.service pkcs11-daemon.service urfkill.service ipwatchd.service xfs_healer@.service; do
	ok "$u: OnFailure= is emptied, then names sparky-stereo-service-problem@" '[ "$(directive $u.d OnFailure | tr "\\n" " ")" = " sparky-stereo-service-problem@%n.service " ]'
	ok "$u: the engine's top-level handler is masked by name" '[ "$(readlink "$SD/$u.d/50-sparky-stereo-problems.conf")" = /dev/null ]'
done
ok "the failure handler unit is installed" '[ -s "$SD/sparky-stereo-service-problem@.service" ] && grep -q "^ExecStart=/usr/bin/sparky-stereo-service-defaults record %i$" "$SD/sparky-stereo-service-problem@.service"'
# U14, U15, U16: no condition hides a service whose need is not met
ok "U14 snmptt: no condition skips it when Net::IP is missing" '[ -z "$(directive snmptt.service.d ExecCondition)" ]'
ok "U15 pkcs11-daemon: no condition skips it when its library is missing" '[ -z "$(directive pkcs11-daemon.service.d ExecCondition)" ]'
ok "U16 urfkill: no condition skips it when ConsoleKit is missing" '[ -z "$(directive urfkill.service.d ConditionPathExists)" ]'
# U53 xfs_healer: our findmnt check, which took a failed findmnt for "not XFS", is gone; upstream's check stays
ok "U53 xfs_healer: the drop-in adds and resets no ExecCondition" '[ -z "$(directive xfs_healer@.service.d ExecCondition)" ] && ! grep -q "^ExecCondition" "$SD/xfs_healer@.service.d/sparky-stereo.conf"'
# U53 ipwatchd: the probe's three answers
cond=$(directive ipwatchd.service.d ExecCondition)
fresh; printf '2: eth0    inet 192.0.2.5/24 brd 192.0.2.255 scope global eth0\n' >"$F/addresses"
out=$(PATH=$F:$PATH LANG=C sh -c "$cond" 2>&1); rc=$?
ok "U53 ipwatchd: an IPv4 address: needed (0)" '[ "$rc" = 0 ]'
: >"$F/addresses"
out=$(PATH=$F:$PATH LANG=C sh -c "$cond" 2>&1); rc=$?
ok "U53 ipwatchd: no IPv4 address yet: a skip (1), said, nothing kept" '[ "$rc" = 1 ] && echo "$out" | grep -q "waits for an IPv4 address" && [ ! -e "$(rec ipwatchd.service)" ]'
: >"$F/ip-fails"
out=$(PATH=$F:$PATH INVOCATION_ID=probe-run LANG=C sh -c "$cond" 2>&1); rc=$?
ok "U53 ipwatchd: a failed probe is not \"no address\": the unit fails (255)" '[ "$rc" = 255 ]'
ok "U53 ipwatchd: the failed probe is said with ip's own error" 'echo "$out" | grep -q "It could not be determined whether ipwatchd.service is needed: .*ip -4 -o address show scope global failed (Cannot open netlink socket"'
ok "U53 ipwatchd: and kept" 'kept ipwatchd.service LOCAL5'
# the failure handler keeps the probe's precise reason for the same run
printf 'Result=exit-code\nExecMainStatus=0\nInvocationID=probe-run\n' >"$F/show"; : >"$F/journal"
PATH=$F:$PATH LANG=C $T record ipwatchd.service 2>/dev/null
ok "U53 ipwatchd: the failure handler keeps the probe's reason for that run" 'kept ipwatchd.service LOCAL5'
rm -f "$F/ip-fails"; printf '2: eth0    inet 192.0.2.5/24 scope global eth0\n' >"$F/addresses"
PATH=$F:$PATH LANG=C sh -c "$cond" >/dev/null 2>&1
ok "U53 ipwatchd: a probe that works again clears it" '[ ! -e "$(rec ipwatchd.service)" ]'

# the failure handler: what each service needs, from its own output and configuration
R=$(mktemp -d); export SPARKY_SERVICE_DEFAULTS_ROOT=$R
mkdir -p "$R/etc/snmp" "$R/etc/default" "$R/usr/lib/x86_64-linux-gnu/urfkill"
printf '[General]\nipv6_enable = 1\n' >"$R/etc/snmp/snmptt.ini"
fresh; printf 'Result=exit-code\nExecMainStatus=2\nInvocationID=run-1\n' >"$F/show"
printf 'Could not load the Perl module Net::IP!  If ipv6_enable\nis enabled then the Net::IP module is required.\ndied at /usr/sbin/snmptt line 527.\n' >"$F/journal"
out=$(PATH=$F:$PATH LANG=C $T record snmptt.service 2>&1)
if perl -MNet::IP -e 1 2>/dev/null; then
	echo "FAIL U14: Net::IP is installed in this bench, the missing-module case cannot run"; FAILS=$((FAILS + 1))
else
	ok "U14 snmptt without Net::IP: said with what to install" 'echo "$out" | grep -q "turns IPv6 on (ipv6_enable = 1), which needs the Perl module Net::IP" && echo "$out" | grep -q "sudo apt-get install libnet-ip-perl"'
	ok "U14 snmptt: kept with its own lines as evidence" 'kept snmptt.service LOCAL2 && grep -q "Could not load the Perl module Net::IP" "$(rec snmptt.service)"'
fi
ok "the handler reads only that run's lines" 'grep -q "_SYSTEMD_INVOCATION_ID=run-1" "$F/journal-args"'
fresh; printf 'PKCS11_DAEMON_SOCKET="tls://[::1]:2345"\nPKCS11_LIB=/usr/lib/softhsm/libsofthsm2.so\n' >"$R/etc/default/pkcs11-daemon"
printf "couldn't open library: /usr/lib/softhsm/libsofthsm2.so: cannot open shared object file: No such file or directory\n" >"$F/journal"
out=$(PATH=$F:$PATH LANG=C $T record pkcs11-daemon.service 2>&1)
ok "U15 pkcs11-daemon: said with the library, where it is set and what to do" 'echo "$out" | grep -q "The token service (pkcs11-daemon) could not start: couldn.t open library: /usr/lib/softhsm/libsofthsm2.so: cannot open shared object file: No such file or directory. Its PKCS#11 library is /usr/lib/softhsm/libsofthsm2.so (PKCS11_LIB in /etc/default/pkcs11-daemon)"'
ok "U15 pkcs11-daemon: kept" 'kept pkcs11-daemon.service LOCAL3'
fresh; printf 'binary bytes org.freedesktop.ConsoleKit.Manager more bytes' >"$R/usr/lib/x86_64-linux-gnu/urfkill/urfkilld"
printf '<warning> failed to setup proxy for consolekit: Error calling StartServiceByName for org.freedesktop.ConsoleKit\n<warning> Could not startup; bailing out\n' >"$F/journal"
out=$(PATH=$F:$PATH LANG=C $T record urfkill.service 2>&1)
ok "U16 urfkill built for ConsoleKit: said with the reason, and that radio switches work without it" 'echo "$out" | grep -q "tracks sessions through ConsoleKit, and this system runs systemd-logind instead. Radio switches keep working without it"'
ok "U16 urfkill: kept" 'kept urfkill.service LOCAL4'
fresh; printf '<warning> failed to setup arbitrator\n<warning> Could not startup; bailing out\n' >"$F/journal"
out=$(PATH=$F:$PATH LANG=C $T record urfkill.service 2>&1)
ok "U16 urfkill failing for another reason is not blamed on ConsoleKit" 'kept urfkill.service LOCAL1 && echo "$out" | grep -q "The service urfkill.service could not start: <warning> Could not startup; bailing out"'
fresh; printf '/: Input/output error\n' >"$F/journal"
out=$(PATH=$F:$PATH LANG=C $T record xfs_healer@-.service 2>&1)
ok "U53 xfs_healer@-: a real failure is said with the healer's own line, and kept" 'kept xfs_healer@-.service LOCAL1 && echo "$out" | grep -q "The service xfs_healer@-.service could not start: /: Input/output error"'
PATH=$F:$PATH $T clear xfs_healer@-.service
ok "a unit that starts clears its record (ExecStartPost)" '[ ! -e "$(rec xfs_healer@-.service)" ]'
unset SPARKY_SERVICE_DEFAULTS_ROOT

# status, dismiss, repair, notify
fresh; printf 'Result=exit-code\nExecMainStatus=1\nInvocationID=run-2\n' >"$F/show"; printf 'it broke\n' >"$F/journal"
PATH=$F:$PATH LANG=C $T record ipwatchd.service 2>/dev/null
out=$(LANG=C $T status 2>&1); rc=$?
ok "status lists the kept problem and exits 1" '[ "$rc" = 1 ] && echo "$out" | grep -q "The service ipwatchd.service could not start: it broke"'
# the session's notifier shows the problems now (sparky-stereo-problems-plasma): notify starts it
NF=$(mktemp -d)
printf '#!/bin/sh\necho "$*" >>%s/systemctl.log\n' "$NF" >"$NF/systemctl"; chmod 755 "$NF/systemctl"
PATH=$NF:$PATH LANG=C $T notify
ok "notify: starts the session's notifier, which shows every problem" 'grep -q "^--user start sparky-stereo-problems-notifier.service$" "$NF/systemctl.log"'
LANG=pt_BR.UTF-8 $T status >"$F/status-pt" 2>&1
ok "status in the session's language" 'grep -q "O serviço ipwatchd.service não pôde iniciar: it broke" "$F/status-pt"'
: >"$F/restart-fails"
out=$(PATH=$F:$PATH LANG=C $T repair 2>&1); rc=$?
ok "repair: a unit that fails again stays kept (exit 1)" '[ "$rc" = 1 ] && kept ipwatchd.service LOCAL1 && grep -q "restart ipwatchd.service" "$F/restarted"'
rm -f "$F/restart-fails"
out=$(PATH=$F:$PATH LANG=C $T repair 2>&1); rc=$?
ok "repair: a unit that starts is cleared (exit 0)" '[ "$rc" = 0 ] && echo "$out" | grep -q "Repaired: ipwatchd.service" && [ ! -e "$(rec ipwatchd.service)" ]'
PATH=$F:$PATH LANG=C $T record ipwatchd.service 2>/dev/null
out=$(LANG=C $T dismiss ipwatchd.service 2>&1); rc=$?
ok "dismiss: said, status no longer counts it" '[ "$rc" = 0 ] && LANG=C $T status >/dev/null 2>&1'
ok "dismiss is the engine's Hide: kept listed, hidden for you" 'sparky-stereo-problems list --json | python3 -c "import json,sys; d=[p for p in json.load(sys.stdin) if p.get(\"key\") == \"ipwatchd.service\"]; sys.exit(0 if d and d[0][\"hidden\"] else 1)"'

# NetworkManager's dispatcher: a check that fails is said and kept
NMD=/usr/lib/NetworkManager/dispatcher.d/90-sparky-stereo-ipwatchd
fresh
if [ -x /usr/sbin/ipwatchd ]; then
	echo "Failed to get unit file state for ipwatchd.service: Connection timed out" >"$F/enabled"
	out=$(PATH=$F:$PATH LANG=C "$NMD" eth0 up 2>&1)
	ok "dispatcher: a failed is-enabled is said and kept" 'kept ipwatchd.service LOCAL7 && echo "$out" | grep -q "NetworkManager could not start ipwatchd.service for the new address"'
	fresh; echo disabled >"$F/enabled"; : >"$F/restarted"
	PATH=$F:$PATH "$NMD" eth0 up >/dev/null 2>&1
	ok "dispatcher: a disabled ipwatchd is left alone" '[ ! -s "$F/restarted" ] && [ ! -e "$(rec ipwatchd.service)" ]'
	echo enabled >"$F/enabled"
	PATH=$F:$PATH "$NMD" eth0 up >/dev/null 2>&1
	ok "dispatcher: an enabled ipwatchd is restarted" 'grep -q "restart ipwatchd.service" "$F/restarted"'
else
	echo "NOTE dispatcher cases need ipwatchd installed (/usr/sbin/ipwatchd); not run"
fi

# the nine languages
for l in en_US pl_PL pt_BR fr_FR de_DE es_ES ja_JP ko_KR zh_CN zh_TW; do
	code=${l%_*}; case $l in pt_BR|zh_CN|zh_TW) code=$l ;; esac
	want=$(sed -n 's/^LOCAL6="%s *\([^%"]*\)"$/\1/p' "$LANGDIR/$code")
	out=$(PATH=$F:$PATH LANG=$l.UTF-8 sh -c ": >$F/addresses; $cond" 2>&1 | head -n1)
	ok "said in $l" '[ -n "$want" ] && case "$out" in "sparky-stereo-service-defaults: ipwatchd.service"*"${want%% *}"*) true ;; *) false ;; esac'
done
echo "failures: $FAILS"
exit $((FAILS > 0))
