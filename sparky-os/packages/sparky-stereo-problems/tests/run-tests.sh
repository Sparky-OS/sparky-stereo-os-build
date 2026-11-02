#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# The engine's tests, against the installed sparky-stereo-problems, in a throwaway container as root (people are made
# with useradd). Each check states what the engine must do; without the engine every one fails. A real systemd is not
# needed here (tests/systemd-tests.sh runs the failed-service drop-in and the journal under one).
# Usage: run-tests.sh   (exit status: the number of failed checks)
set -u
fail=0
ok() { echo "PASS  $1"; }
no() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
B=sparky-stereo-problems
P=sparky-stereo-problems
M=/var/lib/sparky-stereo-problems
W=$(mktemp -d)
for u in alice bob; do id $u >/dev/null 2>&1 || useradd -m $u; done
as() { local u=$1; shift; runuser -u $u -- env -i HOME=/home/$u PATH=/usr/bin:/bin "$@"; }
js() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(($2))" "$1" 2>/dev/null; }
# pyck FILE EXPRESSION: the JSON in FILE is d, and EXPRESSION must be true
pyck() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if ($2) else 1)" "$1" 2>/dev/null; }
reset() { rm -rf $M/* $M/.lock /run/sparky-stereo-problems/* /home/alice/.local/state/sparky-stereo-problems /home/bob/.local/state/sparky-stereo-problems; }

echo "== keep and clear"
reset
$B keep --machine $P demo LOCAL4 "Demo Service" demo.service @LOCAL8 --repair '["true"]' 2>$W/err; rc=$?
check "keep exits 0" "[ $rc = 0 ]"
check "the record is one file in the machine's store" "[ -f $M/${P}_demo.json ] && [ \$(ls $M | wc -l) = 1 ]"
check "it is written whole: no dot-file is left" "[ -z \"\$(ls -A $M | grep -v '^.lock$' | grep '^\\.')\" ]"
check "its file is not writable by others" "[ \$(stat -c %a $M/${P}_demo.json) = 644 ]"
$B list --json >$W/l.json
check "list --json has it, with its title and its text" "pyck $W/l.json 'len(d) == 1 and d[0][\"key\"] == \"demo\" and d[0][\"scope\"] == \"machine\" and d[0][\"title\"] == \"Sparky Stereo OS: a system service failed\"'"
check "the nested @MESSAGE argument is the message itself" "js $W/l.json 'd[0][\"text\"]' | grep -q 'failed: it did not finish in time'"
check "the message id is the name-based UUID of PACKAGE/KEY" "[ \"\$(js $W/l.json 'd[0][\"message_id\"]')\" = \"\$(python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_URL, \"https://sparkylinux.org/problems/$P/LOCAL4\").hex)')\" ]"
$B clear --machine $P demo; rc=$?
check "clear exits 0 and the record goes" "[ $rc = 0 ] && [ ! -e $M/${P}_demo.json ]"
$B list >$W/l.txt
check "list then says no problem is kept" "grep -q 'No problem is kept.' $W/l.txt"
$B clear --machine $P demo; rc=$?
check "clearing a problem that is not kept is done (exit 0)" "[ $rc = 0 ]"

echo "== a problem kept again"
reset
$B keep --machine $P again LOCAL4 "A" a.service @LOCAL8
f1=$(js $M/${P}_again.json '(d["first"], d["id"], d["generation"], d["changed"])')
sleep 2
$B keep --machine $P again LOCAL4 "A" a.service @LOCAL8
f2=$(js $M/${P}_again.json '(d["first"], d["id"], d["generation"], d["changed"])')
t2=$(js $M/${P}_again.json 'd["time"]')
check "kept again with the same message: the same first time, id, generation and change" "[ \"$f1\" = \"$f2\" ]"
check "its last time moves" "[ \"$t2\" != \"\$(python3 -c \"print($f1[0])\")\" ]"
sleep 1
$B keep --machine $P again LOCAL4 "A" a.service @LOCAL9
check "a new message keeps the first time and id, and is a new generation" "[ \"\$(js $M/${P}_again.json '(d[\"first\"], d[\"id\"], d[\"generation\"])')\" = \"\$(python3 -c \"f=$f1; print((f[0], f[1], f[2] + 1))\")\" ]"
check "a new message moves its change time" "[ \"\$(js $M/${P}_again.json 'd[\"changed\"]')\" != \"\$(python3 -c \"print($f1[3])\")\" ]"

echo "== hide is the person's"
reset
$B keep --machine $P hid LOCAL4 "H" h.service @LOCAL8 --repair '["sh","-c","echo still broken; exit 3"]'
as alice $B hide --machine $P hid; rc=$?
check "a person hides the machine's problem without a password (exit 0)" "[ $rc = 0 ]"
as alice $B list --json >$W/a.json; as bob $B list --json >$W/b.json; $B list --json >$W/r.json
check "hidden for that person" "[ \"\$(js $W/a.json 'd[0][\"hidden\"]')\" = True ]"
check "still listed for that person, with its evidence" "pyck $W/a.json 'len(d) == 1 and d[0][\"repair\"] == [[\"sh\", \"-c\", \"echo still broken; exit 3\"]]'"
check "not hidden for another person" "[ \"\$(js $W/b.json 'd[0][\"hidden\"]')\" = False ]"
check "not hidden for root and the command line" "[ \"\$(js $W/r.json 'd[0][\"hidden\"]')\" = False ]"
check "the machine's record is unchanged by a person's hide" "[ \$(stat -c %U $M/${P}_hid.json) = root ] && ! grep -q hidden $M/${P}_hid.json"
check "the hide is kept in the person's own state" "ls /home/alice/.local/state/sparky-stereo-problems/.hidden/machine_${P}_hid >/dev/null"
as alice $B list >$W/a.txt
check "list says it is hidden for you" "grep -q 'hidden for you' $W/a.txt"
$B keep --machine $P hid LOCAL4 "H" h.service @LOCAL8 --repair '["sh","-c","echo still broken; exit 3"]'
as alice $B list --json >$W/a.json
check "kept again with the same message, it keeps its hide" "[ \"\$(js $W/a.json 'd[0][\"hidden\"]')\" = True ]"
$B repair --machine $P hid >$W/rep.out 2>&1; rc=$?
as alice $B list --json >$W/a.json
check "a repair that fails exits with its status (3)" "[ $rc = 3 ]"
check "after a failed repair the problem shows again" "[ \"\$(js $W/a.json 'd[0][\"hidden\"]')\" = False ]"
check "the failed repair is kept as evidence" "pyck $M/${P}_hid.json 'd[\"repairs_failed\"] == 1 and d[\"last_repair\"][\"status\"] == 3 and d[\"last_repair\"][\"output\"] == \"still broken\\n\"'"
check "the failed repair is said" "grep -q 'Repairing the problem hid of sparky-stereo-problems failed: sh -c echo still broken; exit 3 exited with status 3' $W/rep.out"
as alice $B hide --machine $P hid; as alice $B show --machine $P hid
as alice $B list --json >$W/a.json
check "show undoes the hide" "[ \"\$(js $W/a.json 'd[0][\"hidden\"]')\" = False ]"
as alice $B hide --machine $P hid
$B keep --machine $P hid LOCAL4 "H" h.service @LOCAL9 --repair '["true"]'
as alice $B list --json >$W/a.json
check "a hidden problem whose message changes shows again" "[ \"\$(js $W/a.json 'd[0][\"hidden\"]')\" = False ]"
$B clear --machine $P hid; as alice $B list >/dev/null
check "the person's hide of a problem that is over goes with it" "[ ! -e /home/alice/.local/state/sparky-stereo-problems/.hidden/machine_${P}_hid ]"

echo "== repair"
reset
as alice $B keep $P mine LOCAL4 "M" m.service @LOCAL8 --repair '["sh","-c","echo fixing"]' --repair '["true"]'
check "a person's problem is kept in their own store, theirs only" "[ \"\$(stat -c '%U %a' /home/alice/.local/state/sparky-stereo-problems/${P}_mine.json)\" = 'alice 600' ]"
as alice $B repair $P mine >$W/rep.out 2>&1; rc=$?
check "a repair whose commands all succeed exits 0" "[ $rc = 0 ]"
check "its output was shown" "grep -q fixing $W/rep.out"
check "and the problem is over" "[ ! -e /home/alice/.local/state/sparky-stereo-problems/${P}_mine.json ]"
$B keep --machine $P root-only LOCAL4 "R" r.service @LOCAL8 --repair '["true"]'
as alice $B repair --machine $P root-only >$W/rep.out 2>&1; rc=$?
check "a person repairing the machine's problem: exit 1, it needs an administrator, said with how" "[ $rc = 1 ] && grep -q 'needs an administrator: pkexec sparky-stereo-problems repair --machine sparky-stereo-problems root-only' $W/rep.out"
check "and the problem stays" "[ -f $M/${P}_root-only.json ]"
$B keep --machine $P none LOCAL4 "N" n.service @LOCAL8
$B repair --machine $P none >$W/rep.out 2>&1; rc=$?
check "a problem with no repair command: exit 1, said" "[ $rc = 1 ] && grep -q 'has no repair command' $W/rep.out"
$B repair --machine $P nosuch >$W/rep.out 2>&1; rc=$?
check "repairing a problem that is not kept: exit 1, said" "[ $rc = 1 ] && grep -q 'is not kept' $W/rep.out"

echo "== run"
reset
$B run --machine $P step LOCAL34 @LOCAL35 -- sh -c 'echo first line; echo the reason; exit 7' >$W/run.out 2>&1; rc=$?
check "run exits with the command's status (7)" "[ $rc = 7 ]"
check "run shows the command's output as it comes" "grep -q 'the reason' $W/run.out"
check "a failure is kept with the command, its status and the end of its output" "pyck $M/${P}_step.json 'd[\"command\"] == [\"sh\", \"-c\", \"echo first line; echo the reason; exit 7\"] and d[\"status\"] == 7 and d[\"output\"] == \"first line\\nthe reason\\n\"'"
check "its repair is the command itself" "pyck $M/${P}_step.json 'd[\"repair\"] == [d[\"command\"]]'"
check "the message's first two arguments are the command and its status" "$B list | grep -q 'sh -c echo first line; echo the reason; exit 7 failed (exit status 7), so the folders that keep the problems are not made'"
$B run --machine $P step LOCAL34 @LOCAL35 -- true; rc=$?
check "a success clears it (exit 0)" "[ $rc = 0 ] && [ ! -e $M/${P}_step.json ]"
$B run --machine $P gone LOCAL34 @LOCAL35 -- /nonexistent/program >$W/run.out 2>&1; rc=$?
check "a command that cannot start: 127, kept with why" "[ $rc = 127 ] && grep -q 'No such file or directory' $M/${P}_gone.json"

echo "== the language"
reset
$B keep --machine $P lang LOCAL4 "L" l.service @LOCAL8
check "LANGUAGE before LANG" "[ \"\$(env -i LANGUAGE=de:fr LANG=pt_BR.UTF-8 $B languages)\" = 'de:fr:pt_BR:pt:en' ]"
check "LANGUAGE de, LANG pt_BR: said in German" "env -i LANGUAGE=de:fr LANG=pt_BR.UTF-8 $B list | grep -q 'Der Systemdienst L (l.service) ist fehlgeschlagen: er wurde nicht rechtzeitig fertig'"
check "a language without a catalog is passed over (LANGUAGE eo:fr): French" "env -i LANGUAGE=eo:fr LANG=pt_BR.UTF-8 $B list | grep -q 'Le service système L (l.service) a échoué : il ne s’est pas terminé à temps'"
check "LANG alone: Brazilian Portuguese" "env -i LANG=pt_BR.UTF-8 $B list | grep -q 'O serviço do sistema L (l.service) falhou: ele não terminou a tempo'"
check "LC_ALL before LANG" "env -i LC_ALL=ja_JP.UTF-8 LANG=de_DE.UTF-8 $B list | grep -q 'システムサービス L (l.service) が失敗しました: 時間内に終わりませんでした'"
check "LC_MESSAGES before LANG" "env -i LC_MESSAGES=ko_KR.UTF-8 LANG=de_DE.UTF-8 $B list | grep -q '시스템 서비스 L(l.service)이(가) 실패했습니다'"
check "the bare language: fr_CA is French" "env -i LANG=fr_CA.UTF-8 $B list | grep -q 'Le service système L'"
check "Chinese keeps its script: zh_HK is Traditional" "env -i LANG=zh_HK.UTF-8 $B list | grep -q '系統服務 L（l.service）失敗'"
check "zh_SG is Simplified" "env -i LANG=zh_SG.UTF-8 $B list | grep -q '系统服务 L（l.service）失败'"
check "the C locale ignores LANGUAGE, as gettext does: English" "env -i LANG=C.UTF-8 LANGUAGE=de $B list | grep -q 'The system service L (l.service) failed'"
cp /etc/default/locale $W/locale.saved 2>/dev/null
printf 'LANG=pl_PL.UTF-8\n' >/etc/default/locale
check "no locale in the environment: /etc/default/locale (Polish)" "env -i $B list | grep -q 'Usługa systemowa L (l.service) zawiodła: nie zakończyła się na czas'"
if [ -f $W/locale.saved ]; then cp $W/locale.saved /etc/default/locale; else rm -f /etc/default/locale; fi
env -i LANG=de_DE.UTF-8 $B repair --machine $P nosuch >$W/de.out 2>&1
check "a failure is said in the person's language and in English" "grep -q 'Das Problem nosuch von sparky-stereo-problems ist nicht festgehalten.' $W/de.out && grep -q '(en) The problem nosuch of sparky-stereo-problems is not kept.' $W/de.out"

echo "== a record that cannot be written"
reset
as alice $B keep --machine $P denied LOCAL4 "D" d.service @LOCAL8 >$W/denied.out 2>&1; rc=$?
check "a person keeping in the machine's store: exit 1" "[ $rc = 1 ]"
check "said with where and why" "grep -q 'could not be kept in /var/lib/sparky-stereo-problems: Permission denied' $W/denied.out"
as alice mkdir -p /home/alice/.local/state/sparky-stereo-problems
chmod 500 /home/alice/.local/state/sparky-stereo-problems
as alice $B keep $P ro LOCAL4 "D" d.service @LOCAL8 >$W/ro.out 2>&1; rc=$?
check "a read-only person store: exit 1, said" "[ $rc = 1 ] && grep -q 'could not be kept in /home/alice/.local/state/sparky-stereo-problems: Permission denied' $W/ro.out"
chmod 700 /home/alice/.local/state/sparky-stereo-problems
$B keep --machine 'Not_A_Package' k LOCAL4 >$W/bad.out 2>&1; rc=$?
check "a name that is no package: exit 1, said" "[ $rc = 1 ] && grep -q 'Not_A_Package is not a package name.' $W/bad.out"
$B keep --machine $P k LOCAL4 --repair 'not json' >$W/bad.out 2>&1; rc=$?
check "a wrong option value: exit 2" "[ $rc = 2 ]"

echo "== what cannot be read is listed, never left out"
reset
echo '{not json' >$M/${P}_broken.json
$B list >$W/l.txt
check "an unreadable record is listed with why" "grep -q 'This record cannot be read: not a problem record' $W/l.txt"
rm -f $M/${P}_broken.json

echo "== say"
reset
env -i LANG=de_DE.UTF-8 $B say $P LOCAL4 "S" s.service @LOCAL8 >$W/say.out 2>&1; rc=$?
check "say exits 0, in the person's language and English" "[ $rc = 0 ] && grep -q '^sparky-stereo-problems: Der Systemdienst S' $W/say.out && grep -q '^sparky-stereo-problems: (en) The system service S' $W/say.out"
check "say keeps nothing" "[ -z \"\$(ls $M)\" ]"

echo "== pkexec runs only a repair of what root kept"
reset
$B keep --machine $P px LOCAL4 "P" p.service @LOCAL8 --repair '["true"]'
PKEXEC_UID=1000 $B keep --machine $P px2 LOCAL4 >$W/px.out 2>&1; rc=$?
check "under pkexec, keep is refused (exit 2)" "[ $rc = 2 ] && [ ! -e $M/${P}_px2.json ]"
PKEXEC_UID=1000 $B repair --person $P px >$W/px.out 2>&1; rc=$?
check "under pkexec, a person's repair is refused (exit 2)" "[ $rc = 2 ]"
PKEXEC_UID=1000 SPARKY_STEREO_ROOT=/nonexistent $B repair --machine $P px >$W/px.out 2>&1; rc=$?
check "under pkexec, repair --machine runs, and the caller's environment names no store" "[ $rc = 0 ] && [ ! -e $M/${P}_px.json ]"

echo "== the failed-service handler, with systemd's MONITOR_ variables"
reset
env MONITOR_UNIT=broken.service MONITOR_SERVICE_RESULT=exit-code MONITOR_EXIT_CODE=exited MONITOR_EXIT_STATUS=3 \
	MONITOR_INVOCATION_ID=0123456789abcdef0123456789abcdef $B service-failed broken >$W/sf.out 2>&1; rc=$?
R=/run/sparky-stereo-problems/${P}_broken.service.json
check "the handler exits 0 and keeps it for this boot" "[ $rc = 0 ] && [ -f $R ]"
check "with the unit, its exit status as a message, and systemctl restart as the repair" "pyck $R 'd[\"unit\"] == \"broken.service\" and d[\"args\"][1:] == [\"broken.service\", [\"LOCAL5\", \"3\"]] and d[\"repair\"] == [[\"systemctl\", \"restart\", \"broken.service\"]] and d[\"status\"] == 3'"
check "said as the service's failure" "$B list | grep -q '(broken.service) failed: it stopped with exit status 3'"
env MONITOR_UNIT=t.service MONITOR_SERVICE_RESULT=start-limit-hit $B service-failed t
check "start-limit-hit is said as such" "$B list | grep -q '(t.service) failed: it was started too often in a short time'"
env MONITOR_UNIT=k.service MONITOR_SERVICE_RESULT=signal MONITOR_EXIT_STATUS=KILL $B service-failed k
check "a signal is said with its name" "$B list | grep -q '(k.service) failed: it was stopped by signal KILL'"

echo "== the catalog builder"
mkdir -p $W/lang $W/cat
printf 'LOCAL1="Title"\nLOCAL2="Something %%s failed with %%s."\n' >$W/lang/en
printf 'LOCAL1="Titel"\nLOCAL2="Etwas %%s ist mit %%s fehlgeschlagen."\n' >$W/lang/de
$B catalog demo-pkg $W/lang $W/cat --subject LOCAL1 >/dev/null; rc=$?
check "a complete language builds (exit 0), one entry per message, the subject aside" "[ $rc = 0 ] && [ \$(grep -c '^-- ' $W/cat/demo-pkg.catalog) = 1 ] && [ -f $W/cat/demo-pkg.de.catalog ]"
check "each %s becomes the field the journal fills" "grep -q 'Something @SPARKY_ARG1@ failed with @SPARKY_ARG2@.' $W/cat/demo-pkg.catalog"
check "the entry's id is the message id" "grep -q \"^-- \$($B message-id demo-pkg LOCAL2)\$\" $W/cat/demo-pkg.de.catalog"
printf 'LOCAL1="Tytuł"\n' >$W/lang/pl
$B catalog demo-pkg $W/lang $W/cat --subject LOCAL1 >$W/cat.out 2>&1; rc=$?
check "a language that lacks a message fails the build (exit 1), said" "[ $rc = 1 ] && grep -q 'The message LOCAL2 is missing from' $W/cat.out"
printf 'LOCAL1="Tytuł"\nLOCAL2="Coś %%s nie działa."\n' >$W/lang/pl
$B catalog demo-pkg $W/lang $W/cat --subject LOCAL1 >$W/cat.out 2>&1; rc=$?
check "a language with another number of %s fails the build" "[ $rc = 1 ]"
check "the installed catalogs are in journalctl's database (systemd's trigger)" "journalctl --dump-catalog \$($B message-id $P LOCAL4) 2>/dev/null | grep -q 'The system service @SPARKY_ARG1@ (@SPARKY_ARG2@) failed'"
check "and journalctl -x reads them in the person's language" "LANG=de_DE.UTF-8 journalctl --dump-catalog \$($B message-id $P LOCAL4) 2>/dev/null | grep -q 'Der Systemdienst @SPARKY_ARG1@ (@SPARKY_ARG2@) ist fehlgeschlagen'"

echo "== C, C++ and Python"
reset
cat >$W/t.c <<'EOC'
#include <sparky-stereo-problems.h>
#include <stdio.h>
#include <string.h>
int main(void)
{
    const char *args[] = {"C service", "c.service", "@LOCAL8"};
    if (ssp_keep(SSP_MACHINE, "sparky-stereo-problems", "from-c", "LOCAL4", args, 3, "{\"repair\":[[\"true\"]]}") != 0) return 10;
    char *list = ssp_list_json("sparky-stereo-problems", "de");
    if (!list || !strstr(list, "Der Systemdienst C service")) return 11;
    ssp_free(list);
    if (ssp_repair(SSP_MACHINE, "sparky-stereo-problems", "from-c") != 0) return 12;
    if (ssp_keep(SSP_MACHINE, "Bad_Name", "k", "LOCAL4", NULL, 0, NULL) != 1) return 13;
    if (!strstr(ssp_error_en(), "is not a package name")) return 14;
    puts("c ok");
    return 0;
}
EOC
if command -v cc >/dev/null; then
	cc -o $W/t $W/t.c $(pkg-config --cflags --libs sparky-stereo-problems) 2>$W/cc.out && $W/t >$W/c.out 2>&1; rc=$?
	check "C: keep, list in German, repair and a refused name, through the library" "[ $rc = 0 ] && grep -q 'c ok' $W/c.out"
else
	echo "SKIP  C: no compiler in this image"
fi
python3 - >$W/py.out 2>&1 <<'EOP'
import sparky_stereo_problems as p
p.keep('sparky-stereo-problems', 'from-py', 'LOCAL4', ['Py', 'py.service', ['LOCAL5', '9']], scope=p.MACHINE, repair=[['true']])
items = p.list('sparky-stereo-problems', 'fr')
assert any('il s’est arrêté avec le code de sortie 9' in i['text'] for i in items), items
assert p.message_id('sparky-stereo-problems', 'LOCAL4') == items[0]['message_id']
assert p.repair('sparky-stereo-problems', 'from-py', scope=p.MACHINE) == 0
assert p.list('sparky-stereo-problems') == []
try:
    p.keep('Bad_Name', 'k', 'LOCAL4')
except p.Failed as e:
    assert 'is not a package name' in e.english
else:
    raise SystemExit('no failure')
print('python ok')
EOP
check "Python: keep with a message as an argument, list in French, repair, a refused name" "grep -q 'python ok' $W/py.out"

rm -rf "$W"
echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "$fail FAILED")"
exit $fail
