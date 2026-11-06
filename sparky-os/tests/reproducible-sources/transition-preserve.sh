#!/bin/bash
# ORDER 433: a transition rebuild keeps the published source's Lean Code preserve plan (debian/sparky-lean-preserve.json), or stops.
# ORDER 427 found packages/transition-rebuilds/build-in-container.sh writing a +stereo3d2+lc1 source without the plan the published
# +stereo3d1+lc1 source had: plain-from-lc.py removes the plan whatever its option, and the route never gave it back.
# Runs packages/transition-rebuilds/prepare-lc-source.sh (the route's source half) on a small fixture: a published +lc1 source with a
# two-pattern plan, one without a plan, and one whose plan is not in the form lean.debian_prepare writes. A copy of the script with the
# carrying removed (what the route did before) must fail the same checks, so this test can fail.
# Needs dpkg-dev, devscripts (dch), python3, xz; run it in a container, not on the desktop.
# Usage: bash transition-preserve.sh [SPARKY_OS_DIR]
set -uo pipefail
OS=$(cd "${1:-$(dirname "$0")/../..}" && pwd)
T=$(mktemp -d)
trap 'chmod -R u+rwx "$T"; rm -rf "$T"' EXIT
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com PYTHONDONTWRITEBYTECODE=1 LC_ALL=C.UTF-8
STAMP=1793974631
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
RFC=$(python3 "$OS/repo/reproducible.py" rfc2822 $STAMP)

publish() {  # publish ID PLAN-MODE(none|canonical|indented) : a published fixture-1.0-1+lc1 source in $T/pub-ID
	local id=$1 mode=$2 d=$T/pub-$1
	mkdir -p "$d/up/fixture-1.0"
	printf '#!/bin/sh\necho hello\n' > "$d/up/fixture-1.0/hello.sh"
	tar -C "$d/up" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf - fixture-1.0 | xz -9 > "$d/fixture_1.0.orig.tar.xz"
	cp -r "$d/up/fixture-1.0" "$d/tree" && mkdir -p "$d/tree/debian/source"
	printf '3.0 (quilt)\n' > "$d/tree/debian/source/format"
	printf 'Source: fixture\nSection: misc\nPriority: optional\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nBuild-Depends: debhelper-compat (= 13)\nStandards-Version: 4.7.0\n\nPackage: fixture\nArchitecture: all\nDescription: fixture\n fixture for the transition preserve test\n' > "$d/tree/debian/control"
	printf '#!/usr/bin/make -f\n%%:\n\tdh $@\n' > "$d/tree/debian/rules"; chmod +x "$d/tree/debian/rules"
	printf 'Files: *\nCopyright: 2026 Daniel Campos Ramos\nLicense: GPL-3+\n' > "$d/tree/debian/copyright"
	printf 'fixture (1.0-1) unstable; urgency=medium\n\n  * Fixture.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 +0000\n' > "$d/tree/debian/changelog"
	local args=()
	[ "$mode" = none ] || args=(--preserve-source 'src/*_p.h' 'a tool reads the private-header warning comments' --preserve-source 'tests/*' 'test inputs include deliberate comment fixtures')
	(cd "$d/tree" && SOURCE_DATE_EPOCH=$STAMP PYTHONPATH="$OS" python3 -m lean.debian_prepare "$d/tree" 1.0-1+lc1 --toolkit "$OS" "${args[@]}" >"$d/prep.log" 2>&1) || { cat "$d/prep.log"; bad "fixture $id: debian_prepare failed"; return 1; }
	[ "$mode" != indented ] || python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); open(p,"w").write(json.dumps(d, indent=4)+"\n")' "$d/tree/debian/sparky-lean-preserve.json"
	python3 "$OS/repo/reproducible.py" normalize-tree $STAMP "$d/tree"
	mv "$d/tree" "$d/fixture-1.0"
	(cd "$d" && SOURCE_DATE_EPOCH=$STAMP dpkg-source -b fixture-1.0 >/dev/null 2>&1) || { bad "fixture $id: dpkg-source -b failed"; return 1; }
	rm -rf "$d/up" "$d/fixture-1.0"
	printf 'fixture (1.0-2) unstable; urgency=medium\n\n  * Rebuilt for a library transition, no source change.\n' > "$d/entry.txt"
}

route() {  # route SCRIPTDIR ID : the route's source half on pub-ID, in $T/work-ID
	local dir=$1 id=$2 d=$T/pub-$2
	rm -rf "$T/work-$id"; mkdir -p "$T/work-$id"
	(cd "$T" && env WORK="$T/work-$id" SRC="$d" ENTRY="$d/entry.txt" TOOLKIT="$OS" REPRODUCIBLE="$OS/repo/reproducible.py" \
		DSC=fixture_1.0-1+lc1.dsc DSC_SHA256=$(sha256sum "$d/fixture_1.0-1+lc1.dsc" | cut -d' ' -f1) PLAIN_OPTIONS= \
		SOURCE_DATE_EPOCH=$STAMP SOURCE_DATE_RFC2822="$RFC" bash "$dir/prepare-lc-source.sh" >"$T/route-$id.log" 2>&1)
}

publish good canonical && publish none none && publish indented indented || exit 1
dpkg-source --no-copy -x "$T/pub-good/fixture_1.0-1+lc1.dsc" "$T/x-good" >/dev/null 2>&1
[ "$(wc -l < "$T/x-good/debian/sparky-lean-preserve.json")" -eq 4 ] && ok "fixture: the published source holds a two-pattern preserve plan" || { bad "fixture plan"; exit 1; }

# a published source with a plan: the new +lc1 source has the same plan, byte for byte, and the plain source package has none
if route "$OS/packages/transition-rebuilds" good; then
	W=$T/work-good
	cmp -s "$T/x-good/debian/sparky-lean-preserve.json" "$W/lc/source/debian/sparky-lean-preserve.json" \
		&& ok "the plan came through the rebuild byte for byte" || bad "plan differs or is missing: $(tail -3 "$T/route-good.log")"
	[ "$(sed -n '1p' "$W/lc/source/debian/changelog")" = 'fixture (1.0-2+lc1) UNRELEASED; urgency=medium' ] && ok "the new source is 1.0-2+lc1" || bad "new version: $(sed -n 1p "$W/lc/source/debian/changelog")"
	dpkg-source --no-copy -x "$W/plain/fixture_1.0-2.dsc" "$T/x-plain" >/dev/null 2>&1
	{ [ ! -e "$T/x-plain/debian/sparky-lean-preserve.json" ] && [ ! -e "$T/x-plain/debian/sparky-lean-toolkit" ]; } \
		&& ok "the plain source package has neither plan nor toolkit" || bad "the plain source kept Lean Code files"
	(cd "$W/lc" && SOURCE_DATE_EPOCH=$STAMP python3 "$OS/repo/reproducible.py" normalize-tree $STAMP source && dpkg-source -b source >"$T/pack.log" 2>&1) \
		&& tar -tf "$W"/lc/fixture_1.0-2+lc1.debian.tar.xz | grep -x 'debian/sparky-lean-preserve.json' >/dev/null \
		&& ok "the packed +lc1 Debian tarball carries the plan" || bad "the packed source has no plan: $(tail -3 "$T/pack.log")"
else
	cat "$T/route-good.log"; bad "the route failed on a source with a plan"
fi

# a published source without a plan: none appears
if route "$OS/packages/transition-rebuilds" none; then
	[ ! -e "$T/work-none/lc/source/debian/sparky-lean-preserve.json" ] && ok "a source without a plan gets none" || bad "a plan appeared"
else
	cat "$T/route-none.log"; bad "the route failed on a source without a plan"
fi

# a plan not in the form debian_prepare writes: the route stops, names the source and the way on; it never writes a source without the plan
if route "$OS/packages/transition-rebuilds" indented; then
	bad "the route accepted a plan it could not carry unchanged"
else
	grep -q 'prepare-lc-source: fixture' "$T/route-indented.log" && grep -q 'lc-successor.py' "$T/route-indented.log" \
		&& ok "a plan that would change stops the route with the source named and the way on" || bad "stop message: $(tail -3 "$T/route-indented.log")"
fi

# red: the route as it was (no carrying, no check) loses the plan, so the checks above can fail
mkdir -p "$T/old" && python3 - "$OS/packages/transition-rebuilds/prepare-lc-source.sh" "$T/old/prepare-lc-source.sh" <<'PY'
import re, sys
from pathlib import Path
s = Path(sys.argv[1]).read_text()
a = s.index('PRESERVE=()\n'); b = s.index('# shellcheck disable=SC2086')
s = s[:a] + 'PRESERVE=()\n' + s[b:]
a = s.index('if [ -e "$WORK/published-preserve.json" ]')
Path(sys.argv[2]).write_text(s[:a])
PY
if route "$T/old" good; then
	[ ! -e "$T/work-good/lc/source/debian/sparky-lean-preserve.json" ] && ok "red: without the carrying the new source has no plan (today's main before ORDER 433)" || bad "red: the plan survived without the carrying, so this test cannot fail"
else
	cat "$T/route-good.log"; bad "red: the old route failed to run"
fi

[ $fail = 0 ] && echo "PASS transition preserve" || echo "FAILED"
exit $fail
