#!/bin/bash
# sparky-stereo-wine's checks (ORDER 252c, J21), in a throwaway container (root): the generated Dolphin entry, and the
# worker against a recording stand-in for wine. Usage: run.sh   (the recipe is the folder above this one)
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
M=$T/root/usr/share/kio/servicemenus/sparky-stereo-wine.desktop

echo "== the Dolphin entry"
for type in $(sed -n 's/^MimeType=//p' "$M" | tr ';' ' '); do
	check "MimeType $type is a type or an alias of shared-mime-info" sh -c "grep -qx '$type' /usr/share/mime/types || grep -q '^$type ' /usr/share/mime/aliases"
done
check "programs and installers are offered" grep -qx 'MimeType=application/x-ms-dos-executable;application/x-dosexec;application/vnd.microsoft.portable-executable;application/x-ms-ne-executable;application/x-msi;' "$M"
check "libraries (.dll only types) are not offered" sh -c "! grep -q 'x-msdownload' '$M'"
check "entry calls the runner for the pack" grep -q '^Exec=sparky-stereo-integration run wine -- %F$' "$M"
for l in en pl pt_BR fr de es ja ko zh_CN zh_TW; do
	check "name in $l" grep -q "^Name\(\[$l\]\)\?=." "$M"
done
check "the pack names wine" grep -qx 'program=wine' "$T/root/usr/share/sparky-stereo/integrations.d/wine.conf"
check "no default handler is registered (no mimeapps or desktop entry in the pack)" sh -c "[ -z \"\$(find '$T/root' -name '*.list' -o -path '*/applications/*')\" ]"
check "a file named setup.exe is detected as an offered type (shared-mime-info globs)" sh -c "grep -E '^[0-9]+:application/(vnd.microsoft.portable-executable|x-dosexec|x-ms-dos-executable|x-msdownload):\\*\\.exe' /usr/share/mime/globs2 | head -1 | grep -q ."
check "a file named setup.msi is detected as application/x-msi" grep -q '^[0-9]*:application/x-msi:\*\.msi' /usr/share/mime/globs2

echo "== the worker, with a recording wine"
mkdir -p /usr/share/sparky/sparky-stereo-wine /usr/lib/sparky-stereo/wine "$T/bin"
cp "$T/gen"/lang/* /usr/share/sparky/sparky-stereo-wine/
install -m755 "$HERE/bin/run" /usr/lib/sparky-stereo/wine/run
printf '#!/bin/sh\nprintf "%%s|%%s|%%s|%%s\\n" "$1" "$2" "$3" "$(pwd)" >> "%s/called"\n' "$T" > "$T/bin/wine"
chmod +x "$T/bin/wine"
export PATH=$T/bin:$PATH
S=/usr/lib/sparky-stereo/wine/run
mkdir -p "$T/data/a folder"; echo x > "$T/data/a folder/setup program.exe"; echo x > "$T/data/b.msi"; echo x > "$T/data/-dash.exe"
rm -f "$T/called"; "$S" -- "$T/data/a folder/setup program.exe"; rc=$?
check "exe: exit 0" [ $rc = 0 ]
check "exe: wine start /unix ./file, in the file's folder" [ "$(cat "$T/called")" = "start|/unix|./setup program.exe|$T/data/a folder" ]
rm -f "$T/called"; "$S" -- "$T/data/b.msi"
check "msi: the same command" [ "$(cat "$T/called")" = "start|/unix|./b.msi|$T/data" ]
rm -f "$T/called"; "$S" -- "$T/data/-dash.exe"
check "name starting with a dash: ./-dash.exe" [ "$(cat "$T/called")" = "start|/unix|./-dash.exe|$T/data" ]
rm -f "$T/called"; "$S" -- "$T/data/b.msi" "$T/data/a folder/setup program.exe"
check "two files: both started" [ "$(wc -l < "$T/called")" = 2 ]
cp "$T/bin/wine" "$T/bin/wine.ok"
printf '#!/bin/sh\necho "wine: cannot start" >&2\nexit 3\n' > "$T/bin/wine"
rm -f "$T/called"; "$S" -- "$T/data/b.msi" 2> "$T/err"; rc=$?
check "wine cannot start the file: exit 1" [ $rc = 1 ]
check "wine cannot start the file: the file and the status are said" grep -q "Wine could not start $T/data/b.msi (it ended with exit status 3)" "$T/err"
LANG=de_DE.UTF-8 "$S" -- "$T/data/b.msi" 2> "$T/err"
check "wine cannot start the file: said in German" grep -q 'Wine konnte .* nicht starten (Exit-Status 3)' "$T/err"
LANG=zh_TW.UTF-8 "$S" -- "$T/data/b.msi" 2> "$T/err"
check "wine cannot start the file: said in Traditional Chinese" grep -q '無法啟動' "$T/err"
LANG=ko_KR.UTF-8 "$S" -- "$T/data/b.msi" 2> "$T/err"
check "wine cannot start the file: said in Korean, with what FILE is" grep -q 'wine start /unix 파일 (파일은 해당 파일의 경로입니다)\.' "$T/err"
mv "$T/bin/wine.ok" "$T/bin/wine"
rm -f "$T/called"; "$S" -- "$T/data/missing.exe" "$T/data/b.msi" 2> "$T/err"; rc=$?
check "a missing file among two: exit 1" [ $rc = 1 ]
check "a missing file: named" grep -q "Cannot run $T/data/missing.exe" "$T/err"
check "a missing file: the other one still runs" [ "$(cat "$T/called")" = "start|/unix|./b.msi|$T/data" ]
LANG=ja_JP.UTF-8 "$S" -- "$T/data/missing.exe" 2> "$T/err"
check "missing file in Japanese" grep -q '実行できません' "$T/err"
rm -f "$T/called"; "$S" -- "$T/data" 2> "$T/err"; rc=$?
check "a folder is refused" sh -c "[ $rc = 1 ] && [ ! -e '$T/called' ]"
rm -f "$T/called"; "$S" 2> "$T/err"; rc=$?
check "nothing selected: exit 2, said" sh -c "[ $rc = 2 ] && grep -q 'Select the Windows program' '$T/err'"

echo "== the runner, with and without wine"
export SPARKY_STEREO_INTEGRATIONS_D=$T/root/usr/share/sparky-stereo/integrations.d
export SPARKY_STEREO_INTEGRATION_LANGDIR=$HERE/../sparky-stereo-integration/lang
RUNNER=$HERE/../sparky-stereo-integration/bin/sparky-stereo-integration
sed -i "s|^worker=.*|worker=$S|" "$SPARKY_STEREO_INTEGRATIONS_D/wine.conf"
rm -f "$T/called"; bash "$RUNNER" run wine -- "$T/data/b.msi"; rc=$?
check "runner starts the worker when wine is present" sh -c "[ $rc = 0 ] && [ -e '$T/called' ]"
rm -f "$T/called" "$T/bin/wine"; bash "$RUNNER" run wine -- "$T/data/b.msi" > "$T/out" 2>&1; rc=$?
check "runner without wine: not run, not clean" sh -c "[ $rc != 0 ] && [ ! -e '$T/called' ]"
check "runner without wine: says which program is missing" grep -q wine "$T/out"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "all checks passed"
