#!/bin/bash
# build-sparky-display-tool.py's recommendsFirst (row 933): without the field the upstream Recommends is kept as it is;
# with it the edition's provider leads the alternatives and every upstream one stays; a name already listed, or a
# control with no Recommends line, is refused with the reason and nothing is built.
# Runs the real builder on a small fixture tool, in a Lean Code build image (dpkg-dev, git, the lean toolkit's needs).
# BUILDER=FILE runs another builder (the one before the field, for the red run).
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
toolkit=$(cd "$here/../../.." && pwd)
builder=${BUILDER:-$toolkit/repo/build-sparky-display-tool.py}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PYTHONPATH="$toolkit" PYTHONDONTWRITEBYTECODE=1
export GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@invalid GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@invalid
upstream='firefox-esr | firefox | chromium'
failures=0

inputs() { # $1 folder, $2 Recommends line or empty
	local src=$1/src/sparky-demo-1 deb=$1/deb
	mkdir -p "$src/bin" "$src/lang" "$src/share" "$deb/DEBIAN" "$deb/usr/bin" "$deb/usr/share/sparky/sparky-demo" \
		"$deb/usr/share/applications" "$deb/usr/share/doc/sparky-demo"
	printf '#!/bin/sh\nOSCODE="`cat /etc/lsb-release | grep CODENAME | cut -d= -f2`"\necho "$OSCODE"\n' >"$src/bin/sparky-demo"
	printf 'TITLE=Demo\n' >"$src/lang/en"
	printf '[Desktop Entry]\nType=Application\nName=Demo\nExec=sparky-demo\n' >"$src/share/sparky-demo.desktop"
	printf 'Fixture of the display-tool builder test.\n' >"$src/copyright"
	chmod 755 "$src/bin/sparky-demo"
	cp "$src/bin/sparky-demo" "$deb/usr/bin/"; cp "$src/lang/en" "$deb/usr/share/sparky/sparky-demo/"
	cp "$src/share/sparky-demo.desktop" "$deb/usr/share/applications/"; cp "$src/copyright" "$deb/usr/share/doc/sparky-demo/"
	{ printf 'Package: sparky-demo\nVersion: 1\nArchitecture: all\nMaintainer: Fixture <fixture@invalid>\nDepends: yad\n'
	  [ -z "$2" ] || printf 'Recommends: %s\n' "$2"
	  printf 'Section: System\nPriority: optional\nDescription: Demo\n Fixture.\n'; } >"$deb/DEBIAN/control"
	mkdir -p "$1/in"
	tar -C "$1/src" -czf "$1/in/source.tar.gz" sparky-demo-1
	dpkg-deb --root-owner-group -b "$deb" "$1/in/sparky-demo_1_all.deb" >/dev/null
}

case_() { # $1 name, $2 Recommends of the input or empty, $3 recommendsFirst JSON or empty, $4 expected Recommends or "refused: TEXT"
	local dir=$work/$1 field="" status=0
	inputs "$dir" "$2"
	[ -z "$3" ] || field="\"recommendsFirst\": $3, "
	mkdir -p "$dir/recipe"
	printf 'Fixture.\n' >"$dir/recipe/ATTRIBUTIONS.md"
	python3 - "$dir" "$field" <<'PY'
import hashlib, json, sys
from pathlib import Path
d, field = Path(sys.argv[1]), sys.argv[2]
files = {n: hashlib.sha256((d / 'in' / n).read_bytes()).hexdigest() for n in ('source.tar.gz', 'sparky-demo_1_all.deb')}
text = '{"name": "sparky-demo", "version": "1+stereo3d1+lc1", ' + field + '"binary": "sparky-demo_1_all.deb", "files": ' + json.dumps(files) + '}\n'
json.loads(text)
(d / 'recipe/upstream.json').write_text(text)
PY
	git -C "$dir/recipe" init -q && git -C "$dir/recipe" add -A && git -C "$dir/recipe" commit -q -m fixture
	python3 "$builder" "$dir/recipe" "$dir/out" "$dir/in" >"$dir/build.log" 2>&1 || status=$?
	local deb=$dir/out/sparky-demo_1+stereo3d1+lc1_all.deb got
	case $4 in
	refused:*)
		if [ "$status" != 0 ] && [ ! -e "$deb" ] && grep -qF "${4#refused: }" "$dir/build.log"; then echo "PASS $1: refused (${4#refused: })"
		else echo "FAIL $1: expected a refusal naming '${4#refused: }', got exit $status: $(tail -1 "$dir/build.log")"; failures=$((failures + 1)); fi ;;
	*)
		got=$( [ -e "$deb" ] && dpkg-deb -f "$deb" Recommends || echo "no package (exit $status: $(tail -1 "$dir/build.log"))")
		if [ "$got" = "$4" ]; then echo "PASS $1: Recommends: $got"
		else echo "FAIL $1: Recommends: $got; expected $4"; failures=$((failures + 1)); fi ;;
	esac
}

case_ without-field "$upstream" "" "$upstream"
case_ provider-first "$upstream" '["sparky-stereo-browser"]' "sparky-stereo-browser | $upstream"
case_ already-listed "$upstream" '["firefox"]' "refused: firefox is already in the pinned Recommends"
case_ no-recommends "" '["sparky-stereo-browser"]' "refused: the pinned control has no Recommends line"
[ "$failures" = 0 ] && echo "display-tool-recommends: all 4 cases pass" || { echo "display-tool-recommends: $failures of 4 cases fail"; exit 1; }
