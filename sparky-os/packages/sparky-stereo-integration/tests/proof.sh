#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# ORDER 346f-3 (U37, U38): an integration catalogue that cannot be read stops the install and is told through the problem engine
# (a program the catalogue does not list still installs alone), and a failed or empty command-not-found refresh in the postinst is
# told and kept. Fake konsole (records what would be installed) and fake update-command-not-found; run as root in a container.
# Usage: proof.sh BIN LANGDIR POSTINST [CATALOGDIR]      exit 0 only when every case matches
set -u
BIN=${1:?the sparky-stereo-integration script}; LANGDIR=${2:?its language folder}; POSTINST=${3:?the package postinst}; CAT=${4:-/nonexistent}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home XDG_STATE_HOME=$T/state SPARKY_STEREO_INTEGRATION_UI=none SPARKY_STEREO_INTEGRATION_LANGDIR=$LANGDIR \
	SPARKY_STEREO_INTEGRATIONS_D=$T/none SPARKY_STEREO_PROBLEMS_CATALOG=$CAT:/usr/lib/systemd/catalog
mkdir -p "$HOME" "$XDG_STATE_HOME" "$T/bin"; chmod 755 "$T"; chmod 777 "$HOME" "$XDG_STATE_HOME"
fails=0
ok() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
kept() { sparky-stereo-problems list --json sparky-stereo-integration 2>/dev/null | python3 -c 'import json,sys; print(" ".join(sorted(r["key"] for r in json.load(sys.stdin))))'; }
cat >"$T/bin/konsole" <<EOS
#!/bin/sh
shift 5
echo "\$*" >>"$T/installs"
EOS
cat >"$T/bin/awk-broken" <<'EOS'
#!/bin/sh
echo "awk: cannot run" >&2
exit 2
EOS
chmod +x "$T/bin/konsole" "$T/bin/awk-broken"
export PATH=$T/bin:$PATH
printf 'okprog\tpack-a pack-b\n' >"$T/good.map"
: >"$T/empty.map"
run() { # run MAP [LANG]: install okprog; status in $status, what apt would get in $T/installs
	rm -f "$T/installs"
	SPARKY_STEREO_INTEGRATIONS_MAP=$1 LANG=${2:-en_US.UTF-8} LC_ALL= bash "$BIN" install "${3:-okprog}" >"$T/out" 2>"$T/err"; status=$?
}
installs() { cat "$T/installs" 2>/dev/null || echo none; }
clear_all() { rm -rf "$XDG_STATE_HOME/sparky-stereo-problems"; sparky-stereo-problems clear --all sparky-stereo-integration >/dev/null 2>&1; }

echo "== U37: the catalogue"
clear_all
run "$T/missing.map"
[ "$status" = 1 ] && [ "$(installs)" = none ]; ok $? "catalogue missing: nothing installed, exit $status, installs: $(installs)"
[ "$(kept)" = catalogue ]; ok $? "catalogue missing: the person is told and it is kept (kept: '$(kept)')"
grep -q "missing.map" "$T/err"; ok $? "catalogue missing: the message names the file"
run "$T/good.map"
[ "$status" = 0 ] && [ "$(installs)" = "okprog pack-a pack-b" ]; ok $? "catalogue back: installs the program and its packs ($(installs)), exit $status"
[ -z "$(kept)" ]; ok $? "catalogue back: the problem is over (kept: '$(kept)')"
mkdir "$T/dir.map"; run "$T/dir.map"
[ "$status" = 1 ] && [ "$(installs)" = none ] && [ "$(kept)" = catalogue ]; ok $? "catalogue is a folder: nothing installed, kept"
clear_all
cp "$T/good.map" "$T/locked.map"; chmod 000 "$T/locked.map"
rm -f "$T/installs"
if [ "$(id -u)" = 0 ]; then
	setpriv --reuid=65534 --regid=65534 --clear-groups env SPARKY_STEREO_INTEGRATIONS_MAP="$T/locked.map" HOME="$T/home" XDG_STATE_HOME="$T/state" bash "$BIN" install okprog >"$T/out" 2>"$T/err"; status=$?
else
	run "$T/locked.map"
fi
chmod 644 "$T/locked.map"
[ "$status" = 1 ] && [ "$(installs)" = none ] && [ "$(kept)" = catalogue ]; ok $? "catalogue unreadable: nothing installed, kept, exit $status"
clear_all
rm -f "$T/installs"
PATH=$T/bin:$PATH SPARKY_STEREO_INTEGRATIONS_MAP=$T/good.map bash -c 'ln -sf "$1/bin/awk-broken" "$1/bin/awk"; PATH="$1/bin:$PATH" bash "$2" install okprog' _ "$T" "$BIN" >"$T/out" 2>"$T/err"; status=$?
rm -f "$T/bin/awk"
[ "$status" = 1 ] && [ "$(installs)" = none ] && [ "$(kept)" = catalogue ]; ok $? "awk fails on the catalogue: nothing installed, kept (exit $status)"
clear_all
run "$T/good.map" en_US.UTF-8 otherprog
[ "$status" = 0 ] && [ "$(installs)" = otherprog ] && [ -z "$(kept)" ]; ok $? "program not in a readable catalogue: installs alone, nothing kept ($(installs))"
run "$T/empty.map"
[ "$status" = 0 ] && [ "$(installs)" = okprog ] && [ -z "$(kept)" ]; ok $? "empty catalogue: installs alone, nothing kept ($(installs))"
if [ -d "$CAT" ]; then
	run "$T/missing.map" pt_BR.UTF-8
	grep -q "catálogo" "$T/err"; ok $? "the message is told in the person's language (pt_BR): $(head -c 120 "$T/err")"
	for l in en pl pt_BR fr de ja ko zh_CN zh_TW; do
		t=$(sparky-stereo-problems text --person --lang $l sparky-stereo-integration catalogue 2>&1)
		[ -n "$t" ] && ! printf '%s' "$t" | grep -q "^$"; ok $? "kept record text in $l: $(printf '%s' "$t" | head -c 70)"
	done
fi
clear_all

echo "== U38: the command-not-found refresh in the postinst"
DB=/var/lib/command-not-found/commands.db
mkdir -p /var/lib/command-not-found; rm -f "$DB"
mk_ucnf() { printf '#!/bin/sh\n%s\n' "$1" >"$T/bin/update-command-not-found"; chmod +x "$T/bin/update-command-not-found"; }
post() { sh "$POSTINST" configure >"$T/pout" 2>"$T/perr"; pstatus=$?; }
mk_ucnf 'echo "E: The cache could not be written" >&2; exit 1'; rm -f "$DB"; post
[ "$pstatus" = 0 ]; ok $? "refresh fails: the package still configures (exit $pstatus)"
[ "$(kept)" = suggestions ]; ok $? "refresh fails: it is told and kept (kept: '$(kept)')"
sparky-stereo-problems list --json sparky-stereo-integration 2>&1 | grep -q "cache could not be written"; ok $? "refresh fails: the record carries the command's own error"
mk_ucnf 'exit 0'; rm -f "$DB"; post
[ "$pstatus" = 0 ] && [ "$(kept)" = suggestions ]; ok $? "refresh leaves the index empty: kept (kept: '$(kept)')"
mk_ucnf "echo data >$DB"; rm -f "$DB"; post
[ "$pstatus" = 0 ] && [ -z "$(kept)" ] && [ -s "$DB" ]; ok $? "refresh works: nothing kept, index filled"
mk_ucnf 'exit 1'; echo data >"$DB"; post
[ "$pstatus" = 0 ] && [ -z "$(kept)" ]; ok $? "index already filled: refresh not run, nothing kept"
mk_ucnf 'exit 1'; rm -f "$DB"; post; mk_ucnf "echo data >$DB"; post
[ -z "$(kept)" ]; ok $? "repaired by the next configure: the problem is over"
rm -f "$T/bin/update-command-not-found"; rm -f "$DB"; post
[ "$pstatus" = 0 ] && [ "$(kept)" = suggestions ]; ok $? "update-command-not-found missing: told and kept (kept: '$(kept)')"
clear_all; rm -f "$DB"
echo "failures: $fails"
[ "$fails" = 0 ]
