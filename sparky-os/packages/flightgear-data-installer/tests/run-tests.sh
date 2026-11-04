#!/bin/bash
# Logic tests of flightgear-data-installer, run as root in a disposable Debian container with the package installed.
# They replace the recorded values by those of a small fixture archive (the real archive is 1.75 GiB), so each case runs in seconds;
# the full run with the real recorded values is a separate test. Exit status 0 only when every check passes.
# shellcheck disable=SC2010   # the tests check that nothing of ours is left with ls and grep, as they always did
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
mkdir -p "$W/fx/fgdata_2024_1/gui" "$W/fx/fgdata_2024_1/Nasal" "$W/fx/fgdata_2024_1/Aircraft/c172p" "$W/fx/fgdata_2024_1/Textures/Trees"
echo 2024.1.5 >"$W/fx/fgdata_2024_1/version"
echo '<x/>' >"$W/fx/fgdata_2024_1/gui/x.xml"
echo 'print("a");' >"$W/fx/fgdata_2024_1/Nasal/a.nas"
echo '<x/>' >"$W/fx/fgdata_2024_1/Aircraft/c172p/c172p.xml"
echo '#!/usr/bin/perl' >"$W/fx/fgdata_2024_1/Textures/Trees/convert.pl"
head -c 3000000 /dev/urandom >"$W/fx/fgdata_2024_1/Aircraft/c172p/model.bin"
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
tree_state() { { find "$DATA" "$STATE" "$CACHE" /usr/share/games -maxdepth 6 2>/dev/null | grep -v -e '/lock$' -e '\.txz$' -e '/parts\.' -e 'cache/flightgear-data-installer$' -e 'lib/flightgear-data-installer$'; } | sort; }
leftovers() { ! ls -d /usr/share/games/.flightgear-data-installer.* "$CACHE"/*.txz "$CACHE"/parts.* "$STATE"/pending.* "$STATE"/files.list "$STATE"/installed 2>/dev/null | grep -q .; }
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
check "hash mismatch: the downloaded file is gone and nothing is placed" bash -c "! ls $CACHE/*.txz $CACHE/parts.* $STATE/files.list 2>/dev/null | grep -q . && [ ! -e $DATA/version ]"

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
check "failure while placing: the verified download is kept and the message says so" bash -c "[ \$(cat $CACHE/parts.*/part.* | wc -c) -eq $SIZE ] && grep -q 'stays in $CACHE' $OUTF"
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

# 6 the good run, beside files that belong to another package (flightgear's own)
mkdir -p "$DATA/Nasal" "$DATA/gui"
echo mine >"$DATA/Nasal/sparky-stereo.nas"
echo other >"$DATA/gui/other.xml"
run install
check "install: exit status 0 ($RC)" test "$RC" -eq 0
check "install: says it is done" grep -q "is installed in $DATA" "$OUTF"
check "install: version file is there" test "$(cat "$DATA/version")" = 2024.1.5
check "install: nested files are there" test -f "$DATA/Aircraft/c172p/c172p.xml"
check "install: the other package's file is intact" test "$(cat "$DATA/Nasal/sparky-stereo.nas")" = mine
check "install: nothing is world-writable" bash -c "! find $DATA -perm -0002 | grep -q ."
check "install: the script that is run stays executable" test -x "$DATA/Textures/Trees/convert.pl"
check "install: the archive downloaded is removed afterwards" bash -c "! ls $CACHE/*.txz $CACHE/parts.* 2>/dev/null | grep -q ."
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

# 6b parallel ranges over HTTPS (a local server with byte ranges; its certificate is the only one curl is told to trust)
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$W/srv.key" -out "$W/srv.crt" -days 2 -subj /CN=127.0.0.1 -addext "subjectAltName=IP:127.0.0.1" >/dev/null 2>&1
export CURL_CA_BUNDLE=$W/srv.crt
serve() {
	local mode=$1 port=$2
	rm -f "$W/srv.log"
	python3 "${TESTSRC:-/tests}/range-server.py" "$port" "$W/FlightGear-2024.1.5-data.txz" "$mode" "$W/srv.log" "$W/srv.crt" "$W/srv.key" >"$W/srv.out" 2>&1 &
	SRV=$!
	for _ in $(seq 1 50); do (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null && break; sleep 0.1; done
}
unserve() { kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null; true; }
purge_state() { rm -rf "$DATA" "$STATE" "$CACHE"; }
purge_state
serve normal 18443
printf 'MIRROR_URL=https://127.0.0.1:18443/FlightGear-2024.1.5-data.txz\nPARALLEL=4\n' >/etc/default/flightgear-data-installer
run install
check "parallel: exit status 0 ($RC)" test "$RC" -eq 0
check "parallel: the data is installed and the hash was checked" bash -c "[ \$(cat $DATA/version) = 2024.1.5 ] && grep -q 'Checking the file' $OUTF"
check "parallel: four different byte ranges were asked for, covering the file" bash -c "[ \$(grep -c 'bytes=' $W/srv.log) -eq 4 ] && [ \$(grep -o 'bytes=[0-9]*' $W/srv.log | sort -u | wc -l) -eq 4 ] && grep -q 'bytes=0-' $W/srv.log && grep -q -- '-$((SIZE - 1))' $W/srv.log"
check "parallel: the four requests overlapped in time (connections in parallel, not one after another)" bash -c "[ \$(awk '{print int(\$1*10)}' $W/srv.log | sort -u | wc -l) -le 4 ]"
check "parallel: nothing of the download is left" bash -c "! ls $CACHE/*.txz $CACHE/parts.* 2>/dev/null | grep -q ."
unserve
purge_state

# a connection that is cut half way: the part continues from the bytes it has
serve cut 18444
printf 'MIRROR_URL=https://127.0.0.1:18444/FlightGear-2024.1.5-data.txz\nPARALLEL=3\n' >/etc/default/flightgear-data-installer
run install
check "cut connections: exit status 0 ($RC)" test "$RC" -eq 0
check "cut connections: installed, hash checked, nothing of the download is left" bash -c "[ \$(cat $DATA/version) = 2024.1.5 ] && ! ls $CACHE/parts.* 2>/dev/null | grep -q ."
check "cut connections: every part was asked again from the byte it had (more requests than parts, the later ones start inside a part)" bash -c "[ \$(grep -c 'bytes=' $W/srv.log) -gt 3 ] && [ \$(grep -o 'bytes=[0-9]*' $W/srv.log | sort -u | wc -l) -gt 3 ]"
unserve
purge_state

# a server that ignores byte ranges: the run stops and says so, nothing is installed
serve norange 18445
printf 'MIRROR_URL=https://127.0.0.1:18445/FlightGear-2024.1.5-data.txz\nPARALLEL=4\n' >/etc/default/flightgear-data-installer
run install
check "no ranges: exit status is not 0 ($RC)" test "$RC" -ne 0
check "no ranges: the message says the server does not serve byte ranges and what to do" bash -c "grep -q 'does not serve byte ranges' $OUTF && grep -q 'What to do' $OUTF"
check "no ranges: nothing was installed" test ! -e "$DATA/version"
unserve
purge_state

# a run that is stopped half way (as a killed apt does) continues where it was, and downloads no byte twice
serve slow 18446
printf 'MIRROR_URL=https://127.0.0.1:18446/FlightGear-2024.1.5-data.txz\nPARALLEL=4\n' >/etc/default/flightgear-data-installer
setsid "$BIN" install >"$W/out.txt" 2>&1 &
pid=$!
sleep 3
# only the program itself is told to stop (the way apt stops its child): its curls must end with it
kill -TERM "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
got1=$(cat "$CACHE"/parts.4/part.* 2>/dev/null | wc -c)
check "stopped run: part files stay (some bytes, not all: $got1 of $SIZE)" bash -c "[ $got1 -gt 0 ] && [ $got1 -lt $SIZE ]"
sleep 1
check "stopped run: no curl is left running (zombies of a container without init do not count)" bash -c "! ps -eo stat=,comm= | awk '\$2 == \"curl\" && \$1 !~ /^Z/ { f = 1 } END { exit !f }'"
check "stopped run: nothing is placed" test ! -e "$DATA/version"
: >"$W/srv.log"
run install
check "stopped run, run again: exit status 0 ($RC)" test "$RC" -eq 0
check "stopped run, run again: it says it continues" grep -q "Continuing an earlier download" "$OUTF"
check "stopped run, run again: installed" test "$(cat "$DATA/version")" = 2024.1.5
asked=$(grep -o 'bytes=[0-9]*-[0-9]*' "$W/srv.log" | awk -F'[=-]' '{ s += $3 - $2 + 1 } END { print s + 0 }')
check "stopped run, run again: the bytes asked the second time ($asked) are fewer than the file ($SIZE): nothing was downloaded twice" test "$asked" -lt "$SIZE"
unserve
purge_state

# the setting PARALLEL is checked
for v in 0 17 abc; do
	printf 'MIRROR_URL=file://%s/FlightGear-2024.1.5-data.txz\nPARALLEL=%s\n' "$W" "$v" >/etc/default/flightgear-data-installer
	run install
	check "PARALLEL=$v: refused with the message ($RC)" bash -c "[ $RC -ne 0 ] && grep -q 'PARALLEL' $OUTF && grep -q 'Nothing was installed' $OUTF"
done
purge_state
unset CURL_CA_BUNDLE
conf "file://$W/FlightGear-2024.1.5-data.txz"

# 7 messages: every language has every key and the same placeholders; a language is picked from the locale
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
# 9 remove (not only purge) takes the data away: files, state, cache; an upgrade leaves it
conf "file://$W/FlightGear-2024.1.5-data.txz"
rm -f "$DATA/Nasal/a.nas"
rm -rf "$DATA" "$STATE" "$CACHE"
run install
check "remove: installed first ($RC)" test "$RC" -eq 0
/var/lib/dpkg/info/flightgear-data-installer.postrm upgrade 2.0 >"$W/up.txt" 2>&1
check "remove: an upgrade (postrm upgrade) leaves the data" bash -c "[ -f $DATA/version ] && [ -f $STATE/files.list ]"
/var/lib/dpkg/info/flightgear-data-installer.postrm remove >"$W/remove.txt" 2>&1
check "remove: postrm remove exit status 0" test $? -eq 0
check "remove: the data, the state and the cache are gone" bash -c "[ ! -e $DATA/version ] && [ ! -e $DATA/Aircraft ] && [ ! -e $STATE ] && [ ! -e $CACHE ]"
run install
check "remove: and the data can be installed again ($RC)" test "$RC" -eq 0
mkdir -p "$DATA/Nasal"
echo mine >"$DATA/Nasal/sparky-stereo.nas"
mkdir -p "$DATA/gui"
# 8 purge: the program is already gone when dpkg purges, so the package's own postrm does it; the other package's file in gui/ goes first,
# as removing that package does; Nasal/ still holds the other package's file
rm -f "$DATA/gui/other.xml"
sed -i 's/^MIRROR_URL=.*/MIRROR_URL=/' /etc/default/flightgear-data-installer
/var/lib/dpkg/info/flightgear-data-installer.postrm purge >"$W/purge.txt" 2>&1
check "purge: exit status 0" test $? -eq 0
check "purge: the data it placed is gone" test ! -e "$DATA/Aircraft" -a ! -e "$DATA/version" -a ! -e "$DATA/Nasal/a.nas"
check "purge: a shared folder that is empty by then goes too, the one still holding a file stays" test ! -e "$DATA/gui" -a -d "$DATA/Nasal"
check "purge: the other package's file stays" test "$(cat "$DATA/Nasal/sparky-stereo.nas")" = mine
check "purge: state and cache are gone" test ! -e "$STATE" -a ! -e "$CACHE"
# the data folder was the other package's and is empty by purge time: it goes with the data
conf "file://$W/FlightGear-2024.1.5-data.txz"
run install
check "reinstall: exit status 0 ($RC)" test "$RC" -eq 0
rm -f "$DATA/Nasal/sparky-stereo.nas"
dpkg --remove flightgear-data-installer >"$W/remove2.txt" 2>&1
check "dpkg --remove: exit status 0, the data and the state are gone, the settings file stays until purge" bash -c "[ ! -e $DATA/version ] && [ ! -e $STATE ] && [ -f /etc/default/flightgear-data-installer ]"
dpkg --purge flightgear-data-installer >"$W/purge2.txt" 2>&1
check "dpkg purge: exit status 0" test $? -eq 0
check "dpkg purge: the whole data folder is gone, nothing is left of the package" bash -c "[ ! -e $DATA ] && [ ! -e $STATE ] && [ ! -e $CACHE ] && ! dpkg -L flightgear-data-installer >/dev/null 2>&1"
exit $fail
