#!/bin/bash
# Logic tests of flightgear-data-installer, run as root in a disposable Debian container with the package installed.
# They replace the recorded values by those of a small fixture archive (the real archive is 1.75 GiB), so each case runs in seconds;
# the full run with the real recorded values is a separate test. Exit status 0 only when every check passes.
set -u
umask 022
BIN=/usr/sbin/flightgear-data-installer
LIBD=/usr/share/flightgear-data-installer
LANGD=/usr/share/sparky/flightgear-data-installer
DATA=/usr/share/games/flightgear
STATE=/var/lib/flightgear-data-installer
CACHE=/var/cache/flightgear-data-installer
W=${TESTDIR:-/tmp/fgdi-tests}
fail=0
ok() { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; [ -f "${OUTF:-}" ] && sed "s/^/    output: /" "$OUTF" | head -8; fail=1; }
check() {
	local what=$1
	shift
	if "$@"; then ok "$what"; else bad "$what"; fi
}
rm -rf "$W"
mkdir -p "$W/fx/fgdata_2024_1/Nasal" "$W/fx/fgdata_2024_1/Aircraft/c172p" "$W/fx/fgdata_2024_1/Textures/Trees"
echo 2024.1.5 >"$W/fx/fgdata_2024_1/version"
echo 'print("a");' >"$W/fx/fgdata_2024_1/Nasal/a.nas"
echo '<x/>' >"$W/fx/fgdata_2024_1/Aircraft/c172p/c172p.xml"
echo '#!/usr/bin/perl' >"$W/fx/fgdata_2024_1/Textures/Trees/convert.pl"
chmod 777 "$W/fx/fgdata_2024_1/Aircraft/c172p/c172p.xml" "$W/fx/fgdata_2024_1/Nasal"
(cd "$W/fx" && tar -cJf "$W/FlightGear-2024.1.5-data.txz" fgdata_2024_1)
head -c 1000 /dev/urandom >"$W/bad.txz"
SIZE=$(stat -c %s "$W/FlightGear-2024.1.5-data.txz")
SHA=$(sha256sum "$W/FlightGear-2024.1.5-data.txz" | cut -d' ' -f1)
UNP=$(xz --robot -l "$W/FlightGear-2024.1.5-data.txz" | awk '$1 == "totals" { print $5 }')
cp "$LIBD/recorded" "$W/recorded.real"
cat >"$LIBD/recorded" <<EOT
DATA_VERSION=2024.1.5
FILE_NAME=FlightGear-2024.1.5-data.txz
URL=https://sourceforge.net/projects/flightgear/files/release-2024.1/FlightGear-2024.1.5-data.txz/download
SIZE=$SIZE
SHA256=$SHA
UNPACKED=$UNP
TOP=fgdata_2024_1
EOT
conf() { printf 'MIRROR_URL=%s\n' "$1" >/etc/default/flightgear-data-installer; }
tree_state() { { find "$DATA" "$STATE" "$CACHE" /usr/share/games -maxdepth 6 2>/dev/null | grep -v -e '/lock$' -e '\.txz$' -e 'cache/flightgear-data-installer$' -e 'lib/flightgear-data-installer$'; } | sort; }
leftovers() { ! ls -d /usr/share/games/.flightgear-data-installer.* "$CACHE"/*.txz "$STATE"/pending.* "$STATE"/files.list "$STATE"/installed 2>/dev/null | grep -q .; }
run() { OUTF=$W/out.txt; "$BIN" "$@" >"$OUTF" 2>&1; RC=$?; }
rm -rf "$DATA" "$STATE" "$CACHE"

# 1 no network
conf "https://127.0.0.1:9/FlightGear-2024.1.5-data.txz"
before=$(tree_state)
run install
check "no network: exit status is not 0 ($RC)" test "$RC" -ne 0
check "no network: the message says what failed, that nothing was installed and what to do" grep -q "could not be downloaded.*Nothing was installed.*What to do" "$OUTF"
check "no network: nothing half-made is left" leftovers
check "no network: no data folder was made" test ! -e "$DATA/version"

# 1b no network, the data folder's parent does not exist: no folder is made either
check "no network: no empty folder of ours is left" bash -c "[ ! -e /usr/share/games/flightgear ] && [ ! -e $STATE ] && [ ! -e $CACHE ]"

# 2 hash mismatch
conf "file://$W/bad.txz"
run install
check "hash mismatch: exit status is not 0 ($RC)" test "$RC" -ne 0
check "hash mismatch: the message names both hashes and says the file was deleted" grep -q "does not match the SHA-256.*It was deleted and nothing was installed" "$OUTF"
check "hash mismatch: the downloaded file is gone and nothing is placed" bash -c "! ls $CACHE/*.txz $STATE/files.list 2>/dev/null | grep -q . && [ ! -e $DATA/version ]"

# 3 a user's file that does not match is never changed
cp "$W/bad.txz" "$W/user.txz"
conf ""
sum_before=$(sha256sum "$W/user.txz")
run --file "$W/user.txz"
check "own file with a wrong hash: exit status is not 0 ($RC)" test "$RC" -ne 0
check "own file with a wrong hash: the file is untouched" test "$(sha256sum "$W/user.txz")" = "$sum_before"
check "own file with a wrong hash: message says so" grep -q "Your file was not changed and nothing was installed" "$OUTF"

# 4 a file of another package in the way: nothing is placed
mkdir -p "$DATA/Nasal"
echo other >"$DATA/Nasal/a.nas"
before=$(tree_state)
conf "file://$W/FlightGear-2024.1.5-data.txz"
run install
check "conflict: exit status is not 0 ($RC)" test "$RC" -ne 0
check "conflict: message names the file" grep -q "$DATA/Nasal/a.nas already exists and does not come from this package" "$OUTF"
check "conflict: nothing was added or removed (tree identical)" test "$(tree_state)" = "$before"
check "conflict: the other file is intact" test "$(cat "$DATA/Nasal/a.nas")" = other
rm -rf "$DATA" "$STATE" "$CACHE"

# 5 a failure while placing the files is rolled back
mkdir -p "$DATA/Nasal" "$W/fakebin"
echo mine >"$DATA/Nasal/sparky-stereo.nas"
cat >"$W/fakebin/cp" <<'EOT'
#!/bin/bash
# links the first entries, then fails, as a full disk or a failing disk would
src=${*: -2:1}
dst=${*: -1}
mkdir -p "$dst/Nasal"
/bin/cp -l "$src/Nasal/a.nas" "$dst/Nasal/a.nas"
echo "cp: error writing: No space left on device" >&2
exit 1
EOT
chmod 755 "$W/fakebin/cp"
before=$(tree_state)
run_with_fake() { OUTF=$W/out.txt; PATH=$W/fakebin:$PATH "$BIN" install >"$OUTF" 2>&1; RC=$?; }
conf "file://$W/FlightGear-2024.1.5-data.txz"
run_with_fake
check "failure while placing: exit status is not 0 ($RC)" test "$RC" -ne 0
check "failure while placing: message says nothing was installed" grep -q "could not be unpacked.*nothing was installed" "$OUTF"
find "$DATA" -maxdepth 3 | sort >"$W/after.txt"
check "failure while placing: only the other package's file remains" test "$(cat "$W/after.txt" | tr '\n' ' ')" = "$DATA $DATA/Nasal $DATA/Nasal/sparky-stereo.nas "
check "failure while placing: no state and no staging folder left" bash -c "! ls /usr/share/games/.flightgear-data-installer.* $STATE/files.list $STATE/installed $STATE/pending.* 2>/dev/null | grep -q ."
check "failure while placing: the verified download is kept and the message says so" bash -c "[ -f $CACHE/FlightGear-2024.1.5-data.txz ] && grep -q 'stays in $CACHE' $OUTF"
rm -rf "$DATA" "$STATE" "$CACHE"

# 5b a termination while unpacking (the whole process group, as Ctrl-C or a killed apt does) leaves nothing
cat >"$W/fakebin/tar" <<'EOT'
#!/bin/bash
sleep 30
EOT
chmod 755 "$W/fakebin/tar"
mkdir -p "$DATA/Nasal"
echo mine >"$DATA/Nasal/sparky-stereo.nas"
conf "file://$W/FlightGear-2024.1.5-data.txz"
PATH=$W/fakebin:$PATH setsid "$BIN" install >"$W/out.txt" 2>&1 &
sleep 4
pid=$!
kill -TERM -- "-$pid" 2>/dev/null
wait "$pid" 2>/dev/null
rc=$?
check "termination while unpacking: the run ended with a signal status ($rc)" test "$rc" -ne 0
check "termination while unpacking: no staging folder, no state, no list left" bash -c "! ls /usr/share/games/.flightgear-data-installer.* $STATE/files.list $STATE/installed $STATE/pending.* 2>/dev/null | grep -q ."
check "termination while unpacking: the other package's file remains" test "$(cat "$DATA/Nasal/sparky-stereo.nas")" = mine
rm -f "$W/fakebin/tar"
rm -rf "$DATA" "$STATE" "$CACHE"

# 6 the good run, beside a file that belongs to another package (flightgear's own)
mkdir -p "$DATA/Nasal"
echo mine >"$DATA/Nasal/sparky-stereo.nas"
run install
check "install: exit status 0 ($RC)" test "$RC" -eq 0
check "install: says it is done" grep -q "is installed in $DATA" "$OUTF"
check "install: version file is there" test "$(cat "$DATA/version")" = 2024.1.5
check "install: nested files are there" test -f "$DATA/Aircraft/c172p/c172p.xml"
check "install: the other package's file is intact" test "$(cat "$DATA/Nasal/sparky-stereo.nas")" = mine
check "install: nothing is world-writable" bash -c "! find $DATA -perm -0002 | grep -q ."
check "install: the script that is run stays executable" test -x "$DATA/Textures/Trees/convert.pl"
check "install: the archive downloaded is removed afterwards" test ! -e "$CACHE/FlightGear-2024.1.5-data.txz"
check "install: no staging folder is left" bash -c "! ls -d /usr/share/games/.flightgear-data-installer.* 2>/dev/null | grep -q ."
check "install: the file list does not name the other package's file" bash -c "! grep -q sparky-stereo.nas $STATE/files.list"
check "install: the file list names ours" grep -q "$DATA/Nasal/a.nas" "$STATE/files.list"
conf "https://127.0.0.1:9/none"
run install
check "second run: already installed, no download attempted (exit $RC)" bash -c "[ $RC -eq 0 ] && grep -q 'already installed' $OUTF"
"$BIN" --check
check "--check: exit status 0 while the data is whole" test $? -eq 0
rm -f "$DATA/Nasal/a.nas"
"$BIN" --check
check "--check: exit status is not 0 when a file is missing" test $? -ne 0

# 7 messages: every language has every key and the same placeholders; a language is picked from the locale
cp "$W/recorded.real" "$LIBD/recorded" 2>/dev/null || true
fail_msgs=0
for f in "$LANGD"/*; do
	l=$(basename "$f")
	[ "$(grep -c '^MSG_' "$f")" = "$(grep -c '^MSG_' "$LANGD/en")" ] || { bad "language $l has another number of messages"; fail_msgs=1; }
	while IFS= read -r k; do
		a=$(grep "^$k=" "$LANGD/en" | grep -o '%[s%]' | tr -d '\n')
		b=$(grep "^$k=" "$f" | grep -o '%[s%]' | tr -d '\n')
		[ "$a" = "$b" ] || { bad "language $l: $k placeholders $b differ from English $a"; fail_msgs=1; }
	done < <(grep -o '^MSG_[A-Z_]*' "$LANGD/en")
done
check "messages: nine languages complete with the same placeholders" test "$(ls "$LANGD" | wc -l)" -eq 9 -a "$fail_msgs" -eq 0
for pair in de_DE.UTF-8:"Führen Sie" fr_FR.UTF-8:"Lancez ceci" pl_PL.UTF-8:"Uruchom to" pt_BR.UTF-8:"Execute isto" ja_JP.UTF-8:"管理者として" ko_KR.UTF-8:"관리자 권한" zh_CN.UTF-8:"请以管理员" zh_TW.UTF-8:"請以管理員" en_US.UTF-8:"Run this as"; do
	loc=${pair%%:*}
	want=${pair#*:}
	out=$(setpriv --reuid=65534 --regid=65534 --clear-groups env LC_ALL=$loc "$BIN" install 2>&1)
	check "language $loc" bash -c 'grep -qF -- "$1" <<<"$2"' _ "$want" "$out"
done
# 8 purge (dpkg's own purge: the program is gone by then)
dpkg --purge flightgear-data-installer >"$W/purge.txt" 2>&1
check "purge: exit status 0" test $? -eq 0
check "purge: the data it placed is gone" test ! -e "$DATA/Aircraft" -a ! -e "$DATA/version" -a ! -e "$DATA/Nasal/a.nas"
check "purge: the other package's file stays" test "$(cat "$DATA/Nasal/sparky-stereo.nas")" = mine
check "purge: state and cache are gone" test ! -e "$STATE" -a ! -e "$CACHE"

exit $fail
