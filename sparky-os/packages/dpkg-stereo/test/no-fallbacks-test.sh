#!/bin/bash
# dpkg-stereo's "nothing fails silently" proof (ORDER 346b, rows U19, U20 and U57 of ORDER 343's audit), in a
# throwaway Debian container (root): a demo package with a script, a Python module and a setting, then each failure
# planted on purpose. A step that cannot do what it is for must say what failed, why and what to do, keep it in
# /var/lib/dpkg-stereo/problems, and --repair must fix it once its cause is gone; dpkg's hooks still return 0, so
# dpkg goes on. A verification that did not check a file must never say clean. Each case has its control.
# Usage: no-fallbacks-test.sh DPKG-STEREO-PROGRAM LIB-DIR LANG-DIR WORKDIR
#   (the program to test, the folder holding its lean package, its language files' folder, a scratch folder)
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
CACHE=$(dirname $PY)/__pycache__
OWN=$(python3 -c 'import sys; print("cpython-%d%d" % sys.version_info[:2])')
mkdir -p "$W" /usr/local/bin
d=$W/lean-demo
mkdir -p "$d/DEBIAN" "$d/usr/bin" "$(dirname "$d$PY")" "$d/etc/xdg"
cat > "$d/usr/bin/lean-demo" <<'EOF'
#!/bin/sh
# lean-demo: prints a word. This comment and the four after it are commentary the shell reads and skips.
# The installed program does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.
# A fourth line of commentary, long enough that the projection is worth its pointer line.
# A fifth line of commentary, long enough that the projection is worth its pointer line.
echo demo
EOF
chmod 755 "$d/usr/bin/lean-demo"
cat > "$d$PY" <<'EOF'
# leandemo: a module whose commentary the interpreter skips at every import, five lines of it.
# The installed program does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.
VALUE = 7


def value():
    # inside a function, commentary too
    return VALUE
EOF
cat > "$d/etc/xdg/leandemorc" <<'EOF'
# lean-demo's defaults: this commentary moves to the HR copy, and KConfig reads only the group and key.
# The installed setting does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.
# A fourth line of commentary, long enough that the projection is worth its pointer line.
[General]
Mode=fast
EOF
printf '/etc/xdg/leandemorc\n' > "$d/DEBIAN/conffiles"
printf 'Package: lean-demo\nVersion: 1.0\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: d\n' > "$d/DEBIAN/control"
DEB=$W/lean-demo_1.0_all.deb
dpkg-deb --root-owner-group -b "$d" "$DEB" >/dev/null
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*

fresh() {      # the demo installed anew, no dpkg-stereo state, no fakes, an empty APT cache
	dpkg --purge lean-demo >/dev/null 2>&1
	rm -rf "$S" /var/cache/apt/archives/lean-demo_* /usr/local/bin/apt-get /usr/local/bin/apt-cache \
		/usr/local/bin/busctl /usr/local/bin/python3.98 "$CACHE"
	dpkg -i "$DEB" >/dev/null 2>&1 || bad "demo install"
	mkdir -p "$CACHE"
	python3 -c "import py_compile; py_compile.compile('$PY', cfile='$CACHE/leandemo.$OWN.pyc')"
}
projected() { ! grep -q 'commentary' "$1"; }
kept() { [ -f "$S/problems/$1.json" ] && python3 "$BIN" --problems | grep -q -- "$2"; }
said() { grep -q -- "$1" "$W/err"; }
# apt as a system with no network sees it: the version is listed, and the download fails with APT's own error
fake_offline_apt() {
	printf '#!/bin/sh\necho "E: Failed to fetch file:/srv/demo/lean-demo_1.0_all.deb  Connection failed" >&2\nexit 100\n' > /usr/local/bin/apt-get
	printf '#!/bin/sh\necho " lean-demo |        1.0 | file:/srv/demo ./ Packages"\n' > /usr/local/bin/apt-cache
	chmod 755 /usr/local/bin/apt-get /usr/local/bin/apt-cache
}

echo "== control: the demo projects, and its bytecode is refreshed for the new size"
fresh
ds --project lean-demo > "$W/out" 2> "$W/err"; rc=$?
check "control-project-exit-0" [ $rc = 0 ]
check "control-script-projected" projected /usr/bin/lean-demo
check "control-module-projected" projected $PY
check "control-setting-projected" projected /etc/xdg/leandemorc
check "control-bytecode-refreshed" python3 -c "
import os, sys
data = open('$CACHE/leandemo.$OWN.pyc', 'rb').read()
sys.exit(int.from_bytes(data[12:16], 'little') != os.path.getsize('$PY'))"
check "control-no-problem-kept" [ ! -d "$S/problems" ] || [ -z "$(ls -A "$S/problems")" ]

echo "== U20: a cache that cannot be written (the own interpreter's .pyc is a folder)"
fresh
rm -f "$CACHE/leandemo.$OWN.pyc"; mkdir "$CACHE/leandemo.$OWN.pyc"
ds --project lean-demo > "$W/out" 2> "$W/err"; rc=$?
check "u20-own-exit-1" [ $rc = 1 ]
check "u20-own-kept" kept bytecode "FileExistsError"
check "u20-own-said" said "Python bytecode files could not be refreshed"
check "u20-own-records-saved" grep -q "^$PY" "$S/records/lean-demo.tsv"
python3 "$BIN" --verify lean-demo > "$W/verify" 2>&1
check "u20-own-verify-finds-it" grep -q "3 projected files checked, 0 problems" "$W/verify"

echo "== U20: a cache of an interpreter that is not installed (python3.99)"
fresh
echo stale > "$CACHE/leandemo.cpython-399.pyc"
ds --project lean-demo > "$W/out" 2> "$W/err"; rc=$?
check "u20-missing-exit-1" [ $rc = 1 ]
check "u20-missing-kept" kept bytecode "python3.99 is not installed"

echo "== U20: another interpreter that fails (python3.98 exits 3)"
fresh
echo stale > "$CACHE/leandemo.cpython-398.pyc"
printf '#!/bin/sh\necho "python3.98: cannot start" >&2\nexit 3\n' > /usr/local/bin/python3.98; chmod 755 /usr/local/bin/python3.98
ds --project lean-demo > "$W/out" 2> "$W/err"; rc=$?
check "u20-other-exit-1" [ $rc = 1 ]
check "u20-other-kept" kept bytecode "python3.98 exited 3: python3.98: cannot start"
rm -f /usr/local/bin/python3.98 "$CACHE/leandemo.cpython-398.pyc"
ds --repair > "$W/out" 2> "$W/err"; rc=$?
check "u20-repair-clears" sh -c "[ $rc = 0 ] && [ ! -e '$S/problems/bytecode.json' ]"

echo "== U57: verify --deep with the .deb at hand (control)"
fresh
ds --project lean-demo >/dev/null 2>&1
cp "$DEB" /var/cache/apt/archives/
ds --verify --deep > "$W/out" 2> "$W/err"; rc=$?
check "u57-control-exit-0" [ $rc = 0 ]
check "u57-control-clean" grep -q ' 0 problems' "$W/out"
check "u57-control-no-nodeb" sh -c "! grep -q NODEB '$W/out'"

echo "== U57: verify --deep when the .deb cannot be downloaded"
rm -f /var/cache/apt/archives/lean-demo_*
fake_offline_apt
ds --verify --deep > "$W/out" 2> "$W/err"; rc=$?
check "u57-offline-not-clean-exit-2" [ $rc = 2 ]
check "u57-offline-apt-error-named" grep -q 'apt-get download lean-demo=1.0 exited 100: E: Failed to fetch' "$W/out"
check "u57-offline-summary-says-not-checked" grep -q 'NOT checked against their package' "$W/out"
check "u57-offline-verdict" grep -q 'This check is not complete' "$W/out"

echo "== U57: verify --deep with a damaged .deb in APT's cache"
rm -f /usr/local/bin/apt-get /usr/local/bin/apt-cache
head -c 300 "$DEB" > /var/cache/apt/archives/lean-demo_1.0_all.deb
ds --verify --deep > "$W/out" 2> "$W/err"; rc=$?
check "u57-damaged-not-clean-exit-2" [ $rc = 2 ]
check "u57-damaged-reader-error-named" grep -Eq 'dpkg-deb --fsys-tarfile lean-demo_1.0_all.deb exited [0-9]+|reading lean-demo_1.0_all.deb' "$W/out"

echo "== U57 and U19: restore when the .deb cannot be downloaded, then repaired"
rm -f /var/cache/apt/archives/lean-demo_*
fake_offline_apt
ds --restore lean-demo > "$W/out" 2> "$W/err"; rc=$?
check "restore-offline-exit-1" [ $rc = 1 ]
check "restore-offline-real-reason" grep -q 'stay lean (apt-get download lean-demo=1.0 exited 100: E: Failed to fetch' "$W/out"
check "restore-offline-kept" kept restore "could not be put back"
check "restore-offline-problems-exit-1" sh -c "python3 '$BIN' --problems >/dev/null; [ \$? = 1 ]"
rm -f /usr/local/bin/apt-get /usr/local/bin/apt-cache
cp "$DEB" /var/cache/apt/archives/
ds --repair > "$W/out" 2> "$W/err"; rc=$?
check "restore-repair-exit-0" [ $rc = 0 ]
check "restore-repair-cleared" [ ! -e "$S/problems/restore.json" ]
check "restore-repair-original-back" cmp -s /usr/bin/lean-demo "$d/usr/bin/lean-demo"

echo "== U19: dpkg's post-invoke hook fails (its records folder is a file)"
fresh
mkdir -p $S && : > $S/records
dpkg --post-invoke="python3 $BIN --post-invoke" -i "$DEB" > "$W/out" 2> "$W/err"; rc=$?
check "u19-hook-dpkg-goes-on" sh -c "[ $rc = 0 ] && dpkg-query -W -f='\${Status}' lean-demo | grep -q 'ok installed'"
check "u19-hook-kept" kept post-invoke "NotADirectoryError"
check "u19-hook-said-what" said "Lean Code after dpkg (the post-invoke hook) did not complete: NotADirectoryError"
check "u19-hook-said-what-to-do" said "What to do: sudo dpkg-stereo --repair"
check "u19-hook-problems-exit-1" sh -c "python3 '$BIN' --problems >/dev/null; [ \$? = 1 ]"
rm -f $S/records
check "u19-hook-status-counts" sh -c "python3 '$BIN' --status | grep -q 'Problems kept: 1'"
ds --repair > "$W/out" 2> "$W/err"; rc=$?
check "u19-hook-repair-exit-0" [ $rc = 0 ]
check "u19-hook-repair-projects" projected $PY
check "u19-hook-repair-cleared" sh -c "python3 '$BIN' --problems >/dev/null"

echo "== U19: the same in Brazilian Portuguese, with the English line beside it"
fresh
mkdir -p $S && : > $S/records
LANG=pt_BR.UTF-8 python3 "$BIN" --post-invoke > "$W/out" 2> "$W/err"; rc=$?
check "u19-pt-exit-0" [ $rc = 0 ]
check "u19-pt-said" said "não terminou: NotADirectoryError"
check "u19-pt-english-beside" said "(en) Lean Code after dpkg"

echo "== U19: dpkg's pre-invoke hook fails (its conffile index is a folder)"
fresh
ds --project lean-demo >/dev/null 2>&1
rm -f $S/conffiles.tsv && mkdir $S/conffiles.tsv
dpkg --pre-invoke="python3 $BIN --pre-invoke" -i "$DEB" > "$W/out" 2> "$W/err" < /dev/null; rc=$?
check "u19-pre-dpkg-goes-on" [ $rc = 0 ]
check "u19-pre-kept" kept pre-invoke "IsADirectoryError"
rmdir $S/conffiles.tsv

echo "== U19: the first projection (the postinst's --project) fails"
fresh
mkdir -p $S && : > $S/records
ds --project > "$W/out" 2> "$W/err"; rc=$?
check "u19-project-exit-1" [ $rc = 1 ]
check "u19-project-kept" kept project "NotADirectoryError"
check "u19-project-said" said "The Lean Code projection of the installed packages did not complete"
rm -f $S/records
ds --dismiss project > "$W/out" 2>&1; rc=$?
check "u19-dismiss" sh -c "[ $rc = 0 ] && [ ! -e '$S/problems/project.json' ]"

echo "== U19: the HR copies cannot be written (a pristine copy is gone)"
fresh
ds --project lean-demo >/dev/null 2>&1
rm -rf $S/pristine
ds --fetch-hr > "$W/out" 2> "$W/err"; rc=$?
check "u19-hr-exit-1" [ $rc = 1 ]
check "u19-hr-kept" kept fetch-hr "its pristine copy is missing"
check "u19-hr-said" said "HR copies could not be written"

echo "== notifications: each kept problem once per session, and a failure to show one is said"
mkdir -p "$W/xdg"
printf '#!/bin/sh\necho "$*" >> %s/busctl.calls\n' "$W" > /usr/local/bin/busctl; chmod 755 /usr/local/bin/busctl
rm -f "$W/busctl.calls" "$W/xdg/dpkg-stereo-notified"
XDG_RUNTIME_DIR=$W/xdg python3 "$BIN" --notify > "$W/out" 2> "$W/err"; rc=$?
check "notify-shown" sh -c "[ $rc = 0 ] && grep -q 'Lean Code needs attention' '$W/busctl.calls'"
XDG_RUNTIME_DIR=$W/xdg python3 "$BIN" --notify > "$W/out" 2> "$W/err"
check "notify-once" [ "$(grep -c ' Notify ' "$W/busctl.calls")" = 1 ]
printf '#!/bin/sh\necho "Failed to connect to bus: No medium found" >&2\nexit 1\n' > /usr/local/bin/busctl
rm -f "$W/xdg/dpkg-stereo-notified"
XDG_RUNTIME_DIR=$W/xdg python3 "$BIN" --notify > "$W/out" 2> "$W/err"; rc=$?
check "notify-failure-said" sh -c "[ $rc = 1 ] && grep -q 'could not be shown' '$W/err'"
rm -f /usr/local/bin/busctl

echo "SUMMARY: $passed passed, $failed failed"
exit $fail
