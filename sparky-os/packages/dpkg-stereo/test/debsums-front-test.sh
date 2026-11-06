#!/bin/bash
# dpkg-stereo's debsums front (ORDER 252c, J16), in a throwaway Debian container (root) with debsums installed:
# a demo package with three files Lean Code projects (a script, a module, a setting), one file it leaves alone, and
# its md5sums. debsums alone calls every projected file changed (the control that shows why the front exists);
# `dpkg-stereo --debsums` checks the projected files by their lean hashes and every other file through debsums.
# Each failure is planted on purpose and each has its control.
# Usage: debsums-front-test.sh DPKG-STEREO-PROGRAM LIB-DIR LANG-DIR WORKDIR   (as no-fallbacks-test.sh)
set -u
BIN=$1 LIB=$2 LANGS=$3 W=$4
export DEBIAN_FRONTEND=noninteractive DPKG_STEREO_LIB=$LIB DPKG_STEREO_LANG_DIR=$LANGS LANG=C.UTF-8
unset DPKG_STEREO_DISABLE DPKG_STEREO_NO_PROJECT
fail=0 passed=0 failed=0
ok() { echo "PASS $*"; passed=$((passed + 1)); }
bad() { echo "FAIL $*"; fail=1; failed=$((failed + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
ds() { python3 "$BIN" "$@"; }
S=/var/lib/dpkg-stereo
PY=/usr/lib/python3/dist-packages/leandemo.py
DATA=/usr/share/lean-demo/data.txt
mkdir -p "$W"
d=$W/lean-demo
mkdir -p "$d/DEBIAN" "$d/usr/bin" "$(dirname "$d$PY")" "$d/etc/xdg" "$d$(dirname $DATA)"
cat > "$d/usr/bin/lean-demo" <<'EOS'
#!/bin/sh
# lean-demo: prints a word. This comment and the four after it are commentary the shell reads and skips.
# The installed program does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.
# A fourth line of commentary, long enough that the projection is worth its pointer line.
# A fifth line of commentary, long enough that the projection is worth its pointer line.
echo demo
EOS
chmod 755 "$d/usr/bin/lean-demo"
cat > "$d$PY" <<'EOS'
# leandemo: a module whose commentary the interpreter skips at every import, five lines of it.
# The installed program does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.
VALUE = 7


def value():
    # inside a function, commentary too
    return VALUE
EOS
cat > "$d/etc/xdg/leandemorc" <<'EOS'
# lean-demo's defaults: this commentary moves to the HR copy, and KConfig reads only the group and key.
# The installed setting does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.
# A fourth line of commentary, long enough that the projection is worth its pointer line.
[General]
Mode=fast
EOS
printf 'the data, which Lean Code does not project\n' > "$d$DATA"
printf '/etc/xdg/leandemorc\n' > "$d/DEBIAN/conffiles"
(cd "$d" && find usr -type f -print0 | sort -z | xargs -0 md5sum > DEBIAN/md5sums)
printf 'Package: lean-demo\nVersion: 1.0\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: d\n' > "$d/DEBIAN/control"
DEB=$W/lean-demo_1.0_all.deb
dpkg-deb --root-owner-group -b "$d" "$DEB" >/dev/null
n=$W/nosums-demo
mkdir -p "$n/DEBIAN" "$n/usr/share/nosums-demo"
echo plain > "$n/usr/share/nosums-demo/file"
printf 'Package: nosums-demo\nVersion: 1.0\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: d\n' > "$n/DEBIAN/control"
NDEB=$W/nosums-demo_1.0_all.deb
dpkg-deb --root-owner-group -b "$n" "$NDEB" >/dev/null
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*

fresh() {
	dpkg --purge lean-demo nosums-demo >/dev/null 2>&1
	rm -rf "$S"
	dpkg -i "$DEB" "$NDEB" >/dev/null 2>&1 || bad "demo install"
	# dpkg writes the md5sums a package lacks when it unpacks it; a package from before that has none
	rm -f /var/lib/dpkg/info/nosums-demo.md5sums
	ds --project lean-demo >/dev/null 2>&1
}
projected() { ! grep -q 'commentary' "$1"; }
run() { ds --debsums lean-demo > "$W/out" 2> "$W/err"; rc=$?; }
has() { grep -q -- "$1" "$W/out"; }

echo "== control: debsums alone calls the projected files changed"
fresh
check "control-projected" projected /usr/bin/lean-demo
debsums -s lean-demo > "$W/plain" 2>&1; prc=$?
check "control-debsums-alone-exit-2" [ $prc = 2 ]
check "control-debsums-alone-names-script" grep -q "changed file /usr/bin/lean-demo " "$W/plain"
check "control-debsums-alone-names-module" grep -q "changed file $PY " "$W/plain"

echo "== green: the front passes the same system"
run
check "green-exit-0" [ $rc = 0 ]
check "green-no-debsums-line" sh -c "! grep -q '^DEBSUMS' '$W/out'"
check "green-says-zero" has "debsums: 0 files changed, 0 missing"
check "green-lean-hashes-checked" has "3 projected files checked, 0 problems"
ds --debsums > "$W/out" 2> "$W/err"; rc=$?
check "green-no-names-exit-0" [ $rc = 0 ]
check "green-nosums-information" has "1 packages have no md5sums file"

echo "== red: a file Lean Code does not project is changed"
echo tampered >> "$DATA"
run
check "red-changed-exit-1" [ $rc = 1 ]
check "red-changed-named" has "^DEBSUMS   $DATA (differs from its package's md5sums)"
check "red-changed-counted" has "1 files changed, 0 missing"

echo "== red: that file is gone"
rm -f "$DATA"
run
check "red-missing-exit-1" [ $rc = 1 ]
check "red-missing-named" has "^DEBSUMS   $DATA (missing"

echo "== red: a projected file is changed after projection"
fresh
echo '# edited' >> /usr/bin/lean-demo
run
check "red-projected-exit-1" [ $rc = 1 ]
check "red-projected-named" has "^CHANGED   /usr/bin/lean-demo"

echo "== red: debsums is not installed, the check is incomplete, never clean"
fresh
PATH=$W/nobin /usr/bin/python3 "$BIN" --debsums lean-demo > "$W/out" 2> "$W/err"; rc=$?
check "nodebsums-exit-2" [ $rc = 2 ]
check "nodebsums-says-why" has "apt install debsums"

echo "== red: debsums is asked for a package that is not installed"
ds --debsums no-such-package > "$W/out" 2> "$W/err"; rc=$?
check "unknown-package-exit-2" [ $rc = 2 ]
check "unknown-package-says" has "debsums did not finish"

echo "$passed passed, $failed failed"
exit $fail
