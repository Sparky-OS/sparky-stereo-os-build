#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# ORDER 346f-1 (U27): the installed helper's own paths, in a container as root with the engine and the package installed:
# the failure's text in the nine languages, Repair with the group back, Repair after the wheel is gone, an engine that
# cannot keep (exit 1, said), removal of the package clearing its problems. Exit 0 only when all hold.
set -u
H=/usr/lib/udev/sparky-stereo-wheel-access
fails=0
ok() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/0003:046D:C24F.0001"; : >"$T/0003:046D:C24F.0001/range"; : >"$T/0003:046D:C24F.0001/gain"
D=$T/0003:046D:C24F.0001
groupmod -n games-gone games
$H --mode g+w new-lg4ff "$D" range gain missing 2>/dev/null; ok $((! $? )) "failure exits 1"
n=$(sparky-stereo-problems list --json sparky-stereo-wheel-access | python3 -c 'import json,sys; r=json.load(sys.stdin); print(len(r), r[0]["key"] if r else "")')
[ "$n" = "1 new-lg4ff:0003_046D_C24F.0001" ] || [ "$n" = "1 new-lg4ff:0003:046D:C24F.0001" ]; ok $? "one problem for the wheel: $n"
for l in en pt_BR pl fr de es ja ko zh_CN zh_TW; do
	t=$(sparky-stereo-problems text --machine --lang $l sparky-stereo-wheel-access "$(sparky-stereo-problems list --json sparky-stereo-wheel-access | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["key"])')" 2>&1 | head -1)
	echo "  $l: $t"
	case $t in *range*gain*invalid\ group*) ok 0 "text $l names the controls and the reason" ;; *) ok 1 "text $l names the controls and the reason" ;; esac
done
sparky-stereo-problems repair sparky-stereo-wheel-access >/dev/null 2>&1; ok $((! $? )) "Repair with the group still missing fails and keeps it"
[ "$(sparky-stereo-problems list --json sparky-stereo-wheel-access | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" = 1 ]; ok $? "problem still kept after a failed Repair"
groupmod -n games games-gone
sparky-stereo-problems repair sparky-stereo-wheel-access >/dev/null 2>&1; ok $? "Repair with the group back works"
[ "$(stat -c %G "$D/range")" = games ] && [ -z "$(sparky-stereo-problems list --json sparky-stereo-wheel-access | python3 -c 'import json,sys; r=json.load(sys.stdin); print("x" if r else "")')" ]; ok $? "controls games-owned and problem gone"
# a wheel that is gone: Repair ends the problem
groupmod -n games-gone games
$H new-lg4ff "$D" range 2>/dev/null
groupmod -n games games-gone
rm -rf "$D"
sparky-stereo-problems repair sparky-stereo-wheel-access >/dev/null 2>&1; ok $? "Repair after the wheel was unplugged succeeds"
[ "$(sparky-stereo-problems list --json sparky-stereo-wheel-access | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" = 0 ]; ok $? "problem gone with the wheel"
# the engine cannot keep it
mkdir "$T/w2"; : >"$T/w2/range"; groupmod -n games-gone games
SPARKY_STEREO_WHEEL_ACCESS_ENGINE=false $H x "$T/w2" range 2>"$T/err"; r=$?
[ "$r" = 1 ] && grep -q 'could not be set up' "$T/err"; ok $? "engine that cannot keep: exit 1 and said ($r)"
groupmod -n games games-gone
# removal of the package lets go of its problems
groupmod -n games-gone games; $H x "$T/w2" range 2>/dev/null; groupmod -n games games-gone
dpkg -r sparky-stereo-wheel-access >/dev/null 2>&1
[ "$(sparky-stereo-problems list sparky-stereo-wheel-access)" = "No problem is kept." ]; ok $? "removal clears its problems"
echo "failures: $fails"
exit $((fails > 0))
