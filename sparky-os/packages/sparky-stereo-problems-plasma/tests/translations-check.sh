#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/08
# Copyright 2026 under the GNU GPL3 License
# ORDER 468: the nine required languages on the INSTALLED packages (run as root in a container with sparky-stereo-problems
# and sparky-stereo-problems-plasma installed and the locales generated): every message of the notifier's and the page's
# catalogs is translated (none empty, the same set in every language), the page's metadata and the notifier's events name
# each language, and the engine says the messages of ORDER 468 in each language, differently from English.
# Usage: translations-check.sh   (exit status: the number of failed checks)
set -u
fail=0
ok() { echo "PASS  $1"; }
no() { echo "FAIL  $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
L="de es fr ja ko pl pt_BR zh_CN zh_TW"
declare -A LOC=([de]=de_DE [es]=es_ES [fr]=fr_FR [ja]=ja_JP [ko]=ko_KR [pl]=pl_PL [pt_BR]=pt_BR [zh_CN]=zh_CN [zh_TW]=zh_TW)
PLUGIN=$(find /usr/lib -name kcm_sparkystereo_problems.so -path '*plasma/kcms*' | head -1)
NOTIFYRC=/usr/share/knotifications6/sparky-stereo-problems.notifyrc
check "the page's plugin is installed" "[ -n \"$PLUGIN\" ]"
check "the notifier's events are installed" "[ -f $NOTIFYRC ]"
untranslated() {
	python3 - "$1" <<'EOP'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
bad = 0
for block in text.split('\n\n')[1:]:
    strs = re.findall(r'^msgstr(?:\[\d\])? "(.*)"$', block, re.M)
    if not strs or any(s == '' for s in strs):
        bad += 1
print(bad)
EOP
}
for d in sparky-stereo-problems-plasma kcm_sparkystereo_problems; do
	for l in $L; do
		mo=/usr/share/locale/$l/LC_MESSAGES/$d.mo
		check "$l: $d.mo is installed" "[ -f $mo ]"
		msgunfmt --no-wrap $mo >/tmp/$d.$l.po 2>/dev/null
		check "$l: $d has messages and none is empty" "[ \$(grep -c '^msgid \"' /tmp/$d.$l.po) -gt 20 ] && [ \$(untranslated /tmp/$d.$l.po) = 0 ]"
	done
	check "$d: every language has the same number of messages" "[ \$(for l in $L; do grep -c '^msgid \"' /tmp/$d.\$l.po; done | sort -u | wc -l) = 1 ]"
done
for l in $L; do
	check "$l: the page's name and description are in its metadata" "grep -a -q 'Name\\[$l\\]' $PLUGIN && grep -a -q 'Description\\[$l\\]' $PLUGIN && grep -q '^Name\\[$l\\]=' /usr/share/applications/kcm_sparkystereo_problems.desktop"
	check "$l: every event of the notifier has its name and comment" "python3 - $l <<'EOP'
import re, sys
l = sys.argv[1]
text = open('$NOTIFYRC', encoding='utf-8').read()
bad = []
for sect in re.split(r'^\[', text, flags=re.M)[1:]:
    head = sect.split(']', 1)[0]
    for key in ('Name', 'Comment'):
        if re.search(r'^%s=' % key, sect, re.M) and not re.search(r'^%s\[%s\]=' % (key, l), sect, re.M):
            bad.append(head + ':' + key)
print(bad, file=sys.stderr)
sys.exit(1 if bad else 0)
EOP"
done
# the engine's messages of this order, said in each language and different from English
for l in $L; do
	loc=${LOC[$l]}.UTF-8
	for m in LOCAL19 LOCAL24 LOCAL71 LOCAL14; do
		en=$(env -i LANG=C.UTF-8 sparky-stereo-problems say sparky-stereo-problems $m a b c d 2>&1 | head -1)
		got=$(env -i LANG=$loc sparky-stereo-problems say sparky-stereo-problems $m a b c d 2>&1 | head -1)
		check "$l: the engine says $m in $l, not in English" "[ -n \"$got\" ] && [ \"$got\" != \"$en\" ] && ! echo \"$got\" | grep -q '^sparky-stereo-problems: (en)'"
	done
done
echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "$fail FAILED")"
exit $fail
