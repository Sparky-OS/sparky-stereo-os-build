#!/bin/bash
# sparky-stereo-clamav's checks (ORDER 252c, J20), in a throwaway container (root): the generated Dolphin entry, and the
# worker against a recording stand-in for clamtk. Usage: run.sh   (the recipe is the folder above this one)
# Each failure is planted on purpose and has its control.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
FAILS=0
ok() { echo "  ok:   $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export SPARKY_STEREO_INTEGRATION_UI=none LANG=C.UTF-8
mkdir -p "$T/gen" "$T/root"
python3 "$HERE/gen.py" "$T/gen"
python3 "$HERE/../sparky-stereo-integration/make-pack.py" "$T/gen/pack.json" "$T/root"
M=$T/root/usr/share/kio/servicemenus/sparky-stereo-clamav.desktop

echo "== the Dolphin entry"
for type in $(sed -n 's/^MimeType=//p' "$M" | tr ';' ' '); do
	check "MimeType $type is a type of shared-mime-info" grep -qx "$type" /usr/share/mime/types
done
check "entry is offered for files and folders" grep -qx 'MimeType=inode/directory;application/octet-stream;' "$M"
check "entry is offered for one selection (ClamTk takes one path)" grep -qx 'X-KDE-RequiredNumberOfUrls=1' "$M"
check "entry calls the runner for the pack" grep -q '^Exec=sparky-stereo-integration run clamav -- %F$' "$M"
for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
	check "name in $l" grep -q "^Name\(\[$l\]\)\?=." "$M"
done
check "the pack names clamtk" grep -qx 'program=clamtk' "$T/root/usr/share/sparky-stereo/integrations.d/clamav.conf"

echo "== the worker, with a recording clamtk"
mkdir -p /usr/share/sparky/sparky-stereo-clamav /usr/lib/sparky-stereo/clamav "$T/bin"
cp "$T/gen"/lang/* /usr/share/sparky/sparky-stereo-clamav/
install -m755 "$HERE/bin/scan" /usr/lib/sparky-stereo/clamav/scan
printf '#!/bin/sh\nprintf "%%s\\n" "$#" "$1" > "%s/called"\n' "$T" > "$T/bin/clamtk"
chmod +x "$T/bin/clamtk"
export PATH=$T/bin:$PATH
S=/usr/lib/sparky-stereo/clamav/scan
mkdir -p "$T/data/a folder"; echo x > "$T/data/a file.txt"; echo x > "$T/data/-dash"
rm -f "$T/called"; "$S" -- "$T/data/a file.txt"; rc=$?
check "file: exit 0" [ $rc = 0 ]
check "file: clamtk got exactly the path, no --" [ "$(cat "$T/called")" = "$(printf '1\n%s' "$T/data/a file.txt")" ]
rm -f "$T/called"; "$S" -- "$T/data/a folder"; rc=$?
check "folder: clamtk got the folder" [ "$(sed -n 2p "$T/called")" = "$T/data/a folder" ]
rm -f "$T/called"; (cd "$T/data" && "$S" -- -dash); rc=$?
check "name starting with a dash: passed as ./-dash" [ "$(sed -n 2p "$T/called")" = "./-dash" ]
rm -f "$T/called"; "$S" -- "$T/data/missing" 2> "$T/err"; rc=$?
check "missing path: exit 1" [ $rc = 1 ]
check "missing path: named" grep -q "Cannot scan $T/data/missing" "$T/err"
check "missing path: clamtk not started (it would open its window without scanning)" [ ! -e "$T/called" ]
LANG=de_DE.UTF-8 "$S" -- "$T/data/missing" 2> "$T/err"
check "missing path in German" grep -q 'kann nicht geprüft werden' "$T/err"
rm -f "$T/called"; "$S" -- "$T/data/a file.txt" "$T/data/a folder" 2> "$T/err"; rc=$?
check "two paths: refused, exit 2" [ $rc = 2 ]
check "two paths: clamtk not started" [ ! -e "$T/called" ]
rm -f "$T/called"; "$S" 2> "$T/err"; rc=$?
check "no path: refused, exit 2, said" sh -c "[ $rc = 2 ] && grep -q 'Select one file or one folder' '$T/err'"

echo "== the runner, with and without clamtk"
export SPARKY_STEREO_INTEGRATIONS_D=$T/root/usr/share/sparky-stereo/integrations.d
export SPARKY_STEREO_INTEGRATION_LANGDIR=$HERE/../sparky-stereo-integration/lang
RUNNER=$HERE/../sparky-stereo-integration/bin/sparky-stereo-integration
sed -i "s|^worker=.*|worker=$S|" "$SPARKY_STEREO_INTEGRATIONS_D/clamav.conf"
rm -f "$T/called"; bash "$RUNNER" run clamav -- "$T/data/a file.txt"; rc=$?
check "runner starts the worker when clamtk is present" sh -c "[ $rc = 0 ] && [ -e '$T/called' ]"
rm -f "$T/called" "$T/bin/clamtk"; bash "$RUNNER" run clamav -- "$T/data/a file.txt" > "$T/out" 2>&1; rc=$?
check "runner without clamtk: not run, not clean" sh -c "[ $rc != 0 ] && [ ! -e '$T/called' ]"
check "runner without clamtk: says which program is missing" grep -q clamtk "$T/out"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "all checks passed"
