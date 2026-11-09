#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/09
# Copyright 2026 under the GNU GPL3 License
# ORDER 446: a failed hibernation says why. The installed sparky-stereo-problems reads failed sleep attempts from journals
# built out of fixtures (sleep-fixtures.py, and fixtures/virtiofs-real.export captured from a guest whose hibernation a
# virtio-fs share refused) through systemd-journal-remote, as root in a throwaway container with no systemd running. Each
# check states what the engine must say; the engine before ORDER 446 only says the service failed, and fails them.
# Usage: sleep-tests.sh   (exit status: the number of failed checks)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
fail=0
ok() { echo "PASS  $1"; }
no() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
B=sparky-stereo-problems
P=sparky-stereo-problems
W=$(mktemp -d)
R=$W/root
J=$W/journals
mkdir -p "$R/run/sparky-stereo-problems" "$R/var/lib/sparky-stereo-problems" "$R/proc/self" "$J"
INV=2dd21a977b334a18b8e84fd6cbbe4269
JREMOTE=/usr/lib/systemd/systemd-journal-remote
HIB=systemd-hibernate.service
STH=systemd-suspend-then-hibernate.service
HYB=systemd-hybrid-sleep.service
# mkj NAME EXPORT-FILE: a journal folder of the export
mkj() {
	mkdir -p "$J/$1"
	"$JREMOTE" -o "$J/$1/fixture.journal" --split-mode=none "$2" >"$W/remote-$1.log" 2>&1 || { cat "$W/remote-$1.log"; return 1; }
}
# scenario NAME SCENARIO UNIT
scenario() { python3 "$HERE/sleep-fixtures.py" "$2" "$3" "$W/$1.export" && mkj "$1" "$W/$1.export"; }
# failed NAME UNIT [LANG]: what the failure handler keeps for UNIT out of journal NAME
failed() {
	rm -f "$R"/run/sparky-stereo-problems/*.json
	env SPARKY_STEREO_ROOT="$R" SPARKY_STEREO_PROBLEMS_JOURNAL="$J/$1" MONITOR_UNIT="$2" MONITOR_SERVICE_RESULT=exit-code \
		MONITOR_EXIT_STATUS=1 MONITOR_INVOCATION_ID=$INV LANG=C.UTF-8 LANGUAGE="${3:-en}" $B service-failed "$2" >"$W/sf.out" 2>"$W/sf.err"
}
text() { env SPARKY_STEREO_ROOT="$R" LANG=C.UTF-8 $B text --boot --lang "${2:-en}" $P "$1" 2>&1; }
rec() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if ($2) else 1)" "$R/run/sparky-stereo-problems/${P}_$1.json" 2>/dev/null; }
has() { text "$1" "${3:-en}" | grep -qF -- "$2"; }
hasno() { ! text "$1" | grep -qF -- "$2"; }

echo "== the fixtures are real journals"
check "systemd-journal-remote is there" "[ -x $JREMOTE ]"
mkj real "$HERE/fixtures/virtiofs-real.export"
check "the captured export became a journal folder" "ls $J/real/*.journal >/dev/null 2>&1"
check "journalctl reads the kernel's device field from it" "journalctl -D $J/real -o json --no-pager | grep -q '\"_KERNEL_DEVICE\":\"+pci:0000:00:05.0\"'"
check "and systemd-sleep's SLEEP_STOP line with its ERRNO" "journalctl -D $J/real -o json --no-pager | grep -q '\"ERRNO\":\"95\"'"

echo "== a virtio-fs share that cannot freeze (real capture)"
cat >"$R/proc/self/mountinfo" <<'EOS'
36 1 253:1 / / rw,relatime shared:1 - ext4 /dev/vda2 rw
1069 36 0:43 / /mnt/share rw,relatime shared:1175 - virtiofs sparky-work rw
1070 36 0:44 / /srv/with\040space rw,relatime shared:1176 - virtiofs sparky-os rw
EOS
failed real $HIB; rc=$?
check "the handler succeeds" "[ $rc = 0 ]"
check "the record is kept for this boot under the unit's key" "[ -f $R/run/sparky-stereo-problems/${P}_$HIB.json ]"
T=$(text $HIB)
echo "      $T"
check "it says what could not be done" "grep -qF 'The computer could not hibernate' <<<\"\$T\""
check "it names both devices the kernel named" "grep -qF 'virtio-pci 0000:00:05.0, virtio-pci 0000:00:06.0' <<<\"\$T\""
check "it names the error the kernel returned" "grep -qF 'returned error 95' <<<\"\$T\""
check "it says the share does not support hibernation" "grep -qF 'virtio-fs share' <<<\"\$T\" && grep -qF 'does not support hibernation yet' <<<\"\$T\""
check "it names the share's mount points, a space in one kept" "grep -qF '(/mnt/share, /srv/with space)' <<<\"\$T\""
check "it says what to do: unmount it or stop the program" "grep -qF 'Unmount the virtio-fs share' <<<\"\$T\""
check "it does not offer a blind retry (no repair command)" "rec $HIB 'd[\"repair\"] == []'"
check "it no longer says Repair starts it again" "! grep -qF 'Repair starts it again' <<<\"\$T\""
check "the unit stays its key, for this boot, with the unit's lines kept" "rec $HIB 'd[\"unit\"] == \"$HIB\" and \"Performing sleep operation\" in d[\"output\"]'"
check "the journal event carries the arguments as fields" "rec $HIB 'd[\"args\"][1][0] == \"LOCAL77\" and d[\"args\"][1][1] == \"virtio-pci 0000:00:05.0, virtio-pci 0000:00:06.0\"'"
check "its message has its own MESSAGE_ID (a version 5 UUID)" "$B message-id $P LOCAL72 | grep -qE '^[0-9a-f]{12}5[0-9a-f]{19}$'"
: >"$R/proc/self/mountinfo"
failed real $HIB; T=$(text $HIB)
check "with no share mounted it still says to unmount it, without a list" "grep -qF 'Unmount the virtio-fs share or stop the program' <<<\"\$T\""

echo "== each other kind of cause"
scenario dev device $HIB; failed dev $HIB; T=$(text $HIB); echo "      $T"
check "a driver that refuses: the device, its callback and the error, no retry" "grep -qF 'snd_hda_intel 0000:00:1f.3' <<<\"\$T\" && grep -qF 'azx_freeze_noirq failed with error 110' <<<\"\$T\" && rec $HIB 'd[\"repair\"] == []'"
check "and it says to detach the device or stop its driver" "grep -qF 'Detach the device or stop its driver' <<<\"\$T\""
scenario devs device-suspend $STH; failed devs $STH; T=$(text $STH); echo "      $T"
check "a device that refuses a suspend names the kernel's verb" "grep -qF 'xhci_hcd 0000:00:14.0' <<<\"\$T\" && grep -qF 'step suspend failed with error 16' <<<\"\$T\""
check "for suspend-then-hibernate it says what could not be done in its own words" "grep -qF 'could not hibernate after suspending' <<<\"\$T\""
scenario tsk tasks $HIB; failed tsk $HIB; T=$(text $HIB); echo "      $T"
check "programs that will not freeze are named" "grep -qF 'the busy ones: firefox, rsync' <<<\"\$T\""
check "a cause that can pass keeps a retry, and says what Repair does" "rec $HIB 'd[\"repair\"] == [[\"systemctl\", \"restart\", \"$HIB\"]]' && grep -qF 'This can pass' <<<\"\$T\" && grep -qF 'puts the computer to sleep again' <<<\"\$T\""
scenario lk lockdown $HIB; failed lk $HIB; T=$(text $HIB); echo "      $T"
check "a locked-down kernel is the reason, with the option behind it" "grep -qF 'the kernel is locked down' <<<\"\$T\" && grep -qF 'lockdown= option' <<<\"\$T\""
check "and no retry is offered" "rec $HIB 'd[\"repair\"] == []'"
scenario sw swap-systemd $HIB; failed sw $HIB; T=$(text $HIB); echo "      $T"
check "no swap area big enough: systemd-sleep's own line and the Memory page" "grep -qF 'no swap area is big enough' <<<\"\$T\" && grep -qF 'Failed to find location to hibernate to: No space left on device' <<<\"\$T\" && grep -qF 'Memory page' <<<\"\$T\""
scenario swk swap-kernel $HIB; failed swk $HIB; T=$(text $HIB)
check "the kernel's own swap line (swap.c) is read too" "grep -qF 'PM: Cannot find swap device, try swapon -a' <<<\"\$T\" && rec $HIB 'd[\"repair\"] == []'"
scenario rs resume $HIB; failed rs $HIB; T=$(text $HIB)
check "no resume device is named: where to name it" "grep -qF 'no swap area is named to resume from' <<<\"\$T\" && grep -qF '/etc/initramfs-tools/conf.d/resume' <<<\"\$T\""
scenario kl kernel-line $HIB; failed kl $HIB; T=$(text $HIB)
check "the kernel's own error line is quoted, with a retry said as such" "grep -qF 'the kernel reported: PM: hibernation: Some devices failed to power down, aborting' <<<\"\$T\" && rec $HIB 'len(d[\"repair\"]) == 1' && grep -qF 'Repair starts the operation again' <<<\"\$T\""
scenario sl sleep-line $HIB; failed sl $HIB; T=$(text $HIB)
check "only systemd-sleep's line: it is quoted" "grep -qF 'systemd-sleep reported: Failed to put system to sleep. System resumed again: Input/output error' <<<\"\$T\""
scenario nn none $HIB; failed nn $HIB; T=$(text $HIB)
check "no reason in the journal is said so, never invented" "grep -qF 'the journal of that attempt holds no reason' <<<\"\$T\" && rec $HIB 'len(d[\"repair\"]) == 1'"

echo "== only the attempt's own lines"
scenario old older-attempt-only $HIB; failed old $HIB; T=$(text $HIB)
check "a freeze failure of an earlier attempt is not this one's reason" "grep -qF 'holds no reason' <<<\"\$T\" && ! grep -qF '0000:00:09.0' <<<\"\$T\""
scenario aft after-end $HIB; failed aft $HIB; T=$(text $HIB)
check "a kernel line long after the attempt is not its reason" "grep -qF 'holds no reason' <<<\"\$T\" && ! grep -qF '0000:00:07.0' <<<\"\$T\""
failed real $HYB 2>/dev/null; T=$(text $HYB)
check "a journal of another invocation's unit gives hybrid sleep its own words" "grep -qF 'hibernate while suspending' <<<\"\$T\""

echo "== the nine languages"
failed real $HIB
for l in pl pt_BR fr de ja ko zh_CN zh_TW; do
	T=$(text $HIB $l)
	check "$l: the device is named and the text is not English" "grep -qF 'virtio-pci 0000:00:05.0' <<<\"\$T\" && ! grep -qF 'The computer could not' <<<\"\$T\" && ! grep -qF 'Unmount the virtio-fs' <<<\"\$T\""
done
check "de: says it in German" "has $HIB 'Der Computer konnte nicht in den Ruhezustand wechseln' de"
check "pt_BR: says it in Portuguese" "has $HIB 'O computador não conseguiu hibernar' pt_BR"

echo "== suspend-then-hibernate and hybrid sleep that fall back to suspending"
scenario fb fell-back $STH
sleepattempt() {
	rm -f "$R"/run/sparky-stereo-problems/*.json
	env SPARKY_STEREO_ROOT="$R" SPARKY_STEREO_PROBLEMS_JOURNAL="$J/$1" SERVICE_RESULT="${3:-success}" INVOCATION_ID=$INV LANG=C.UTF-8 $B sleep-attempt "$2" >"$W/sa.out" 2>"$W/sa.err"
}
sleepattempt fb $STH; rc=$?
check "the unit that ended well still tells the failed hibernation (exit 0)" "[ $rc = 0 ] && [ -f $R/run/sparky-stereo-problems/${P}_$STH.json ]"
T=$(text $STH); echo "      $T"
check "with the device and the share's reason" "grep -qF 'virtio-pci 0000:00:05.0' <<<\"\$T\" && grep -qF 'virtio-fs share' <<<\"\$T\""
check "it is not a failed unit's record: no unit, so it ends with the next attempt that works" "rec $STH '\"unit\" not in d or d[\"unit\"] is None'"
scenario ok success $STH
cp "$R"/run/sparky-stereo-problems/${P}_$STH.json "$W/kept.json" 2>/dev/null
rm -f "$R"/run/sparky-stereo-problems/*.json; cp "$W/kept.json" "$R/run/sparky-stereo-problems/${P}_$STH.json"
env SPARKY_STEREO_ROOT="$R" SPARKY_STEREO_PROBLEMS_JOURNAL="$J/ok" SERVICE_RESULT=success INVOCATION_ID=$INV LANG=C.UTF-8 $B sleep-attempt $STH >/dev/null 2>&1
check "an attempt that worked ends the problem of the last" "[ ! -f $R/run/sparky-stereo-problems/${P}_$STH.json ]"
sleepattempt real $STH failure
check "a service that failed is left to its OnFailure handler (nothing kept twice)" "[ ! -f $R/run/sparky-stereo-problems/${P}_$STH.json ]"
sleepattempt ok $HIB
check "a plain hibernation that worked keeps nothing" "ls $R/run/sparky-stereo-problems/*.json >/dev/null 2>&1; [ \$? != 0 ]"
env SPARKY_STEREO_ROOT="$R" $B sleep-attempt failer.service >"$W/bad.out" 2>&1; rc=$?
check "a unit that is not a sleep unit is said, exit 1" "[ $rc = 1 ]"

echo "== other services are untouched"
cat >"$W/other.export" <<'EOS'
__REALTIME_TIMESTAMP=1794260442000000
__MONOTONIC_TIMESTAMP=48000000
_BOOT_ID=494902b537c34e5cb90fc13438456317
PRIORITY=6
SYSLOG_IDENTIFIER=failer
MESSAGE=failer says the disk is gone
_SYSTEMD_UNIT=failer.service
_SYSTEMD_INVOCATION_ID=2dd21a977b334a18b8e84fd6cbbe4269

EOS
mkj other "$W/other.export"
rm -f "$R"/run/sparky-stereo-problems/*.json
env SPARKY_STEREO_ROOT="$R" SPARKY_STEREO_PROBLEMS_JOURNAL="$J/other" MONITOR_UNIT=failer.service MONITOR_SERVICE_RESULT=exit-code MONITOR_EXIT_STATUS=3 \
	MONITOR_INVOCATION_ID=$INV LANG=C.UTF-8 $B service-failed failer.service >/dev/null 2>&1
check "a failed ordinary service is told as before, with its own lines and its restart" "rec failer.service 'd[\"message\"] == \"LOCAL4\" and d[\"args\"][2] == [\"LOCAL5\", \"3\"] and \"disk is gone\" in d[\"output\"] and d[\"repair\"] == [[\"systemctl\", \"restart\", \"failer.service\"]]'"

rm -rf "$W"
echo "failed checks: $fail"
exit $fail
