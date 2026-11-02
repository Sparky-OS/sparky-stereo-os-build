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
check "it is written whole: the record is there and no dot-file is left" "[ -f $M/${P}_demo.json ] && [ -z \"\$(ls -A $M | grep -v '^.lock$' | grep '^\\.')\" ]"
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
check "kept again with the same message: the same first time, id, generation and change" "[ -n \"$f1\" ] && [ \"$f1\" = \"$f2\" ]"
check "its last time moves" "[ -n \"$t2\" ] && [ \"$t2\" != \"\$(python3 -c \"print($f1[0])\")\" ]"
sleep 1
$B keep --machine $P again LOCAL4 "A" a.service @LOCAL9
check "a new message keeps the first time and id, and is a new generation" "[ -n \"$f1\" ] && [ \"\$(js $M/${P}_again.json '(d[\"first\"], d[\"id\"], d[\"generation\"])')\" = \"\$(python3 -c \"f=$f1; print((f[0], f[1], f[2] + 1))\")\" ]"
check "a new message moves its change time" "[ -n \"$f1\" ] && [ -f $M/${P}_again.json ] && [ \"\$(js $M/${P}_again.json 'd[\"changed\"]')\" != \"\$(python3 -c \"print($f1[3])\")\" ]"

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
had=$( [ -e /home/alice/.local/state/sparky-stereo-problems/.hidden/machine_${P}_hid ] && echo yes)
$B clear --machine $P hid; as alice $B list >/dev/null
check "the person's hide of a problem that is over goes with it" "[ \"$had\" = yes ] && [ ! -e /home/alice/.local/state/sparky-stereo-problems/.hidden/machine_${P}_hid ]"

echo "== repair"
reset
as alice $B keep $P mine LOCAL4 "M" m.service @LOCAL8 --repair '["sh","-c","echo fixing"]' --repair '["true"]'
check "a person's problem is kept in their own store, theirs only" "[ \"\$(stat -c '%U %a' /home/alice/.local/state/sparky-stereo-problems/${P}_mine.json)\" = 'alice 600' ]"
as alice $B repair $P mine >$W/rep.out 2>&1; rc=$?
check "a repair whose commands all succeed exits 0" "[ $rc = 0 ]"
check "its output was shown" "grep -q fixing $W/rep.out"
check "and the problem is over" "[ $rc = 0 ] && [ ! -e /home/alice/.local/state/sparky-stereo-problems/${P}_mine.json ]"
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
check "say keeps nothing" "[ $rc = 0 ] && [ -d $M ] && [ -z \"\$(ls $M)\" ]"

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
check "a complete language builds (exit 0), one entry per message, the subject too" "[ $rc = 0 ] && [ \$(grep -c '^-- ' $W/cat/demo-pkg.catalog) = 2 ] && [ -f $W/cat/demo-pkg.de.catalog ]"
check "each %s becomes the field the journal fills" "grep -q 'Something @SPARKY_ARG_A@ failed with @SPARKY_ARG_B@.' $W/cat/demo-pkg.catalog"
check "the entry's id is the message id" "grep -q \"^-- \$($B message-id demo-pkg LOCAL2)\$\" $W/cat/demo-pkg.de.catalog"
printf 'LOCAL1="Tytuł"\n' >$W/lang/pl
$B catalog demo-pkg $W/lang $W/cat --subject LOCAL1 >$W/cat.out 2>&1; rc=$?
check "a language that lacks a message fails the build (exit 1), said" "[ $rc = 1 ] && grep -q 'The message LOCAL2 is missing from' $W/cat.out"
printf 'LOCAL1="Tytuł"\nLOCAL2="Coś %%s nie działa."\n' >$W/lang/pl
$B catalog demo-pkg $W/lang $W/cat --subject LOCAL1 >$W/cat.out 2>&1; rc=$?
check "a language with another number of %s fails the build" "[ $rc = 1 ]"
check "the installed catalogs are in journalctl's database (systemd's trigger)" "journalctl --dump-catalog \$($B message-id $P LOCAL4) 2>/dev/null | grep -q 'The system service @SPARKY_ARG_A@ (@SPARKY_ARG_B@) failed'"
check "and journalctl -x reads them in the person's language" "LANG=de_DE.UTF-8 journalctl --dump-catalog \$($B message-id $P LOCAL4) 2>/dev/null | grep -q 'Der Systemdienst @SPARKY_ARG_A@ (@SPARKY_ARG_B@) ist fehlgeschlagen'"

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

echo "== milestone 2b: the English text, the package's own fields, further sentences"
reset
G=sparky-test-gone
mkdir -p /var/lib/dpkg/info && touch /var/lib/dpkg/info/$G.list
mkdir -p $W/glang
printf 'LOCAL1="Gone test"\nLOCAL2="The thing %%s broke with %%s."\n' >$W/glang/en
printf 'LOCAL1="Test weg"\nLOCAL2="Das Ding %%s ging mit %%s kaputt."\n' >$W/glang/de
$B catalog $G $W/glang /usr/lib/systemd/catalog --subject LOCAL1 >/dev/null
$B keep --machine $G thing LOCAL2 pump 7
check "the English text is kept with the problem" "pyck $M/${G}_thing.json 'd[\"text_en\"] == \"The thing pump broke with 7.\"'"
rm -f /usr/lib/systemd/catalog/$G.catalog /usr/lib/systemd/catalog/$G.de.catalog
env -i LANG=de_DE.UTF-8 $B list --json >$W/gone.json
check "no catalog has its message any more: its English text, never the bare key" "pyck $W/gone.json 'd[0][\"text\"] == \"The thing pump broke with 7.\" and \"LOCAL2\" not in d[0][\"text\"]'"
check "under the engine's own title, in the person's language" "pyck $W/gone.json 'd[0][\"title\"] == \"Sparky Stereo OS: Ein Problem braucht Aufmerksamkeit\"'"
$B keep --machine $P own LOCAL4 "O" o.service @LOCAL8 --details '{"data":{"gpu":"pci-0000:03:00.0","alternatives":[{"id":"a","name":"A"}]},"more":["@LOCAL9",["LOCAL5","3"]]}'
$B list --json >$W/own.json
check "the package's own fields come back as they were kept" "pyck $W/own.json '[x for x in d if x[\"key\"] == \"own\"][0][\"data\"] == {\"gpu\": \"pci-0000:03:00.0\", \"alternatives\": [{\"id\": \"a\", \"name\": \"A\"}]}'"
check "further sentences follow the message, each a message of the package" "pyck $W/own.json '[x for x in d if x[\"key\"] == \"own\"][0][\"text\"].endswith(\"Repair starts it again. it was started too often in a short time it stopped with exit status 3\")'"

echo "== milestone 2b: a package that is removed"
$B keep --machine $G a LOCAL2 x 1; $B keep --machine $G b LOCAL2 y 2
$B clear --all $G; rc=$?
check "clear --all: every problem of the package goes (exit 0)" "[ $rc = 0 ] && [ ! -e $M/${G}_a.json ] && [ ! -e $M/${G}_b.json ] && [ ! -e $M/${G}_thing.json ]"
check "and the others stay" "[ -e $M/${P}_own.json ]"
$B keep --machine $G c LOCAL2 z 3
had=$( [ -e $M/${G}_c.json ] && echo yes)
rm /var/lib/dpkg/info/$G.list
$B list >$W/l.txt
check "the problem of a package that is not installed any more is over: not listed, its record goes" "[ \"$had\" = yes ] && ! grep -q 'sparky-test-gone' $W/l.txt && [ ! -e $M/${G}_c.json ]"

echo "== milestone 2b: a repair whose command keeps the problem again"
reset
$B keep --machine $P again2 LOCAL4 "K" k.service @LOCAL8 --repair '["sparky-stereo-problems","keep","--machine","sparky-stereo-problems","again2","LOCAL4","K","k.service","@LOCAL8"]'
sleep 1
$B repair --machine $P again2 >$W/again.out 2>&1; rc=$?
check "it is not repaired: exit 1, said, kept with the failed repair" "[ $rc = 1 ] && grep -q 'but the problem was kept again' $W/again.out && pyck $M/${P}_again2.json 'd[\"repairs_failed\"] == 1'"

echo "== milestone 2b: the command's own texts in the person's language"
env -i LANG=de_DE.UTF-8 $B frobnicate >$W/use.out 2>&1; rc=$?
check "a wrong use: exit 2, said in German and English, with the usage in German" "[ $rc = 2 ] && grep -q 'unbekannter Befehl frobnicate' $W/use.out && grep -q '(en) unknown command frobnicate' $W/use.out && grep -q 'Aufruf: sparky-stereo-problems BEFEHL' $W/use.out && grep -q 'hält ein Problem fest' $W/use.out"
env -i LANG=ja_JP.UTF-8 $B --help >$W/help.out 2>&1
check "--help in Japanese" "grep -q '使い方: sparky-stereo-problems' $W/help.out && grep -q 'keep \[SCOPE\]' $W/help.out"
check "the polkit action follows the edition's names" "grep -q '<action id=\"org.sparkylinux.sparkystereo.problems.repair\">' /usr/share/polkit-1/actions/org.sparkylinux.sparkystereo.problems.policy"

echo "== milestone 2b: gettext .po files"
mkdir -p $W/po/de $W/po/fr $W/pocat
cat >$W/po/demo.pot <<'EOP'
msgid ""
msgstr ""

msgctxt "@title notification"
msgid "Demo needs a repair"
msgstr ""

msgctxt "@info %1 is a GPU, %2 an address"
msgid "The GPU %1, at %2, is not here."
msgstr ""

msgctxt "@action:button"
msgid "Open"
msgstr ""
EOP
cat >$W/po/de/demo.po <<'EOP'
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"

msgctxt "@title notification"
msgid "Demo needs a repair"
msgstr "Demo braucht eine Reparatur"

msgctxt "@info %1 is a GPU, %2 an address"
msgid "The GPU %1, at %2, is not here."
msgstr "An %2 ist die GPU %1 nicht da."

msgctxt "@action:button"
msgid "Open"
msgstr "Öffnen"
EOP
sed 's/msgstr "An %2 ist die GPU %1 nicht da."/msgstr "Le GPU %1, à %2, n’est pas là."/; s/Demo braucht eine Reparatur/Démo doit être réparée/; s/Öffnen/Ouvrir/' $W/po/de/demo.po >$W/po/fr/demo.po
$B catalog $P-po-test $W/po $W/pocat --subject '@title notification|Demo needs a repair' --context '@info' >/dev/null 2>$W/po.err; rc=$?
check "a gettext po folder builds (exit 0); only the chosen contexts and the subject" "[ $rc = 0 ] && [ \$(grep -c '^-- ' $W/pocat/$P-po-test.catalog) = 2 ] && ! grep -q 'Ouvrir' $W/pocat/$P-po-test.fr.catalog && [ -f $W/pocat/$P-po-test.de.catalog ] && [ -f $W/pocat/$P-po-test.fr.catalog ]"
check "%1 and %2 become fields A and B, in the order each language needs" "grep -q 'An @SPARKY_ARG_B@ ist die GPU @SPARKY_ARG_A@ nicht da.' $W/pocat/$P-po-test.de.catalog"
check "the message is named CONTEXT|MSGID" "grep -q \"^-- \$($B message-id $P-po-test '@info %1 is a GPU, %2 an address|The GPU %1, at %2, is not here.')\$\" $W/pocat/$P-po-test.catalog"
env -i LANG=de_DE.UTF-8 SPARKY_STEREO_PROBLEMS_CATALOG=$W/pocat:/usr/lib/systemd/catalog $B say $P-po-test '@info %1 is a GPU, %2 an address|The GPU %1, at %2, is not here.' Radeon 0000:03:00.0 >$W/po.out 2>&1
check "rendered from a list of catalog folders, in German, the arguments in German's order" "grep -q 'An 0000:03:00.0 ist die GPU Radeon nicht da.' $W/po.out"
sed -i 's/^msgstr "Le GPU %1, à %2, n’est pas là."/#, fuzzy\nmsgstr "Le GPU %1, à %2, n’est pas là."/' $W/po/fr/demo.po
python3 - $W/po/fr/demo.po <<'EOP'
import sys
p = sys.argv[1]
s = open(p).read().replace('\n#, fuzzy\nmsgstr', '\nmsgstr')
s = s.replace('msgctxt "@info %1 is a GPU, %2 an address"', '#, fuzzy\nmsgctxt "@info %1 is a GPU, %2 an address"')
open(p, 'w').write(s)
EOP
$B catalog $P-po-test $W/po $W/pocat --subject '@title notification|Demo needs a repair' --context '@info' >$W/po.err 2>&1; rc=$?
check "a fuzzy translation fails the build, said" "[ $rc = 1 ] && grep -q 'is missing from' $W/po.err"

echo "== milestone 2b: the older problems.py commands, answered by the engine (Steps)"
reset
mkdir -p $W/old
printf '{"step": "moved", "time": "2026-10-01T00:00:00Z", "key": "LOCAL4", "args": ["Old", "old.service", "@LOCAL8"], "command": ["x"], "status": 2, "output": "why\\n", "repair": [["true"]]}\n' >$W/old/moved.json
python3 - $W/old >$W/steps.out 2>&1 <<'EOP'
import os, sys
import sparky_stereo_problems as engine
s = engine.Steps('sparky-stereo-problems', words={'none': 'LOCAL27', 'header': 'LOCAL29', 'since': 'LOCAL22',
                 'repaired': 'LOCAL13', 'failed_again': 'LOCAL14', 'hidden': 'LOCAL19', 'unknown': 'LOCAL18'})
assert s.migrate(sys.argv[1]) and not os.path.exists(sys.argv[1]), 'migrate'
moved = [e for e in s.pending() if e['step'] == 'moved'][0]
assert moved['time'] == '2026-10-01T00:00:00Z' and moved['output'] == 'why\n' and moved['status'] == 2, moved
assert s.record('st1', 'LOCAL4', ['A', 'a.service', ['LOCAL5', '3']], repair=[['true']], quiet=True)
assert 'it stopped with exit status 3' in s.message([e for e in s.pending() if e['step'] == 'st1'][0])
assert s.status() == 1
assert s.dismiss('nosuch') == 1
assert s.repair() == 0 and s.pending() == []
assert s.run('st2', 'LOCAL34', ['@LOCAL35'], ['sh', '-c', 'exit 5']) == 5
assert s.pending()[0]['status'] == 5
print('steps ok')
EOP
check "Steps: migrate keeps the first time, record, message, status, dismiss, repair, run" "grep -q 'steps ok' $W/steps.out"

echo "== milestone 2c: out of memory and a wrong call of the library, said like every failure (LOCAL64 to LOCAL66)"
reset
# a record larger than the memory the engine may take: reading it cannot allocate
python3 -c "import json,sys; json.dump({'package': '$P', 'key': 'big', 'message': 'LOCAL4', 'args': ['x', 'x.service', '@LOCAL8'], 'output': 'x' * (160 << 20)}, open(sys.argv[1], 'w'))" $M/${P}_big.json
# the smallest address space (in steps of 8 MiB) in which the engine starts and says its languages, then 16 MiB more
limit=
for mb in $(seq 16 8 256); do
	if (ulimit -v $((mb * 1024)); $B languages >/dev/null 2>&1); then limit=$(((mb + 16) * 1024)); break; fi
done
check "control: the engine starts in a bounded address space ($((${limit:-0} / 1024)) MiB)" "[ -n \"$limit\" ]"
(ulimit -v ${limit:-1}; env -i LANG=de_DE.UTF-8 $B list --json >/dev/null 2>$W/oom.err); rc=$?
check "out of memory: exit 1" "[ $rc = 1 ]"
check "said in German, from the catalog" "grep -qxF 'sparky-stereo-problems: Kein Speicher mehr: Es war nicht genug freier Speicher dafür vorhanden. Schließen Sie einige Programme, um Speicher freizugeben, und versuchen Sie es erneut.' $W/oom.err"
check "and in English beside it" "grep -qxF 'sparky-stereo-problems: (en) Out of memory: there was not enough free memory to do this. Close some programs to free memory, then try again.' $W/oom.err"
(ulimit -v ${limit:-1}; env -i LANG=ja_JP.UTF-8 $B list >/dev/null 2>$W/oom-ja.err)
check "and in Japanese" "grep -qF 'メモリ不足: これを行うための空きメモリが足りませんでした' $W/oom-ja.err"
(ulimit -v ${limit:-1}; env -i LANG=C.UTF-8 $B list >/dev/null 2>$W/oom-en.err)
check "in English alone when that is the person's language" "[ \"\$(cat $W/oom-en.err)\" = 'sparky-stereo-problems: Out of memory: there was not enough free memory to do this. Close some programs to free memory, then try again.' ]"
env -i LANG=de_DE.UTF-8 python3 - $M/${P}_big.json >$W/oom-lib.out 2>&1 <<'EOP'
import resource
import sparky_stereo_problems as problems
# the address space the process has now, and 32 MiB more: the record cannot be read into it
size = [int(l.split()[1]) for l in open('/proc/self/status') if l.startswith('VmSize:')][0] * 1024
resource.setrlimit(resource.RLIMIT_AS, (size + (32 << 20), resource.RLIM_INFINITY))
try:
    problems.list('sparky-stereo-problems')
    print('listed')
except problems.Failed as error:
    print('local:', error)
    print('en:', error.english)
EOP
check "through the library too: in German and in English" "grep -qxF 'local: Kein Speicher mehr: Es war nicht genug freier Speicher dafür vorhanden. Schließen Sie einige Programme, um Speicher freizugeben, und versuchen Sie es erneut.' $W/oom-lib.out && grep -qxF 'en: Out of memory: there was not enough free memory to do this. Close some programs to free memory, then try again.' $W/oom-lib.out"
rm -f $M/${P}_big.json
env -i LANG=de_DE.UTF-8 python3 - >$W/wrong.out 2>&1 <<'EOP'
import ctypes
import sparky_stereo_problems as problems
try:
    problems.keep('sparky-stereo-problems', 'k', 'LOCAL4', ['A', 'a.service', '@LOCAL8'], scope=7)
except problems.Failed as error:
    print('scope:', error, '|', error.english)
rc = problems._lib.ssp_clear(0, None, b'k')
print('null:', rc, problems._lib.ssp_error().decode(), '|', problems._lib.ssp_error_en().decode())
rc = problems._lib.ssp_keep(0, b'sparky-stereo-problems', b'k', b'LOCAL4', None, 0, b'[1, 2]')
print('details:', rc, problems._lib.ssp_error().decode())
EOP
check "a scope that is none: said in German and in English" "grep -qxF 'scope: sparky-stereo-problems wurde mit einem anderen Bereich als machine, boot oder person aufgerufen. | sparky-stereo-problems was called with a scope other than machine, boot or person.' $W/wrong.out"
check "a missing name: exit 2, said" "grep -qF 'null: 2 sparky-stereo-problems wurde ohne Paket oder Schlüssel aufgerufen' $W/wrong.out"
check "details that are not an object: exit 2, said" "grep -qF 'details: 2 sparky-stereo-problems wurde ohne Paket oder Schlüssel aufgerufen oder mit Argumenten oder Details' $W/wrong.out"

rm -rf "$W"
echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "$fail FAILED")"
exit $fail
