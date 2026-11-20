#!/bin/bash
# ORDER 768b: plain-from-lc.py undoes the kept-hook form that lean.debian_prepare writes when Debian's own debian/rules already
# defines execute_before_dh_auto_configure or execute_before_dh_auto_clean (glib2.0 2.90.1-2: `execute_before_dh_auto_configure:
# cross-tools`). For a kept configure hook, a kept clean hook (one with a recipe), a kept hook with a preserve plan, and a source
# with neither: lean.debian_prepare makes the +lc1 tree, plain-from-lc.py makes it plain again (the original tree byte for byte),
# and lean.debian_prepare on that plain tree gives the same +lc1 tree byte for byte. A rules tail that is not what the step writes
# for that rules file still stops, and the tree is left as it was.
# Red: the plain-from-lc.py before ORDER 768b (commit 665fd06a00, when the checkout has it) stops on the kept form with "the rules
# file does not end with the lc1 targets".
# Needs dpkg-dev, devscripts (dch), python3, git; run it in a container, not on the desktop.
# Usage: bash plain-kept-hook.sh [SPARKY_OS_DIR]
set -uo pipefail
OS=$(cd "${1:-$(dirname "$0")/../..}" && pwd)
T=$(mktemp -d)
trap 'chmod -R u+rwx "$T"; rm -rf "$T"' EXIT
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com PYTHONDONTWRITEBYTECODE=1 LC_ALL=C.UTF-8
export SOURCE_DATE_EPOCH=1793974631
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
PFL="$OS/repo/plain-from-lc.py"
treehash() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1); }

HEAD='#!/usr/bin/make -f\n\n%%:\n\tdh $@\n'
CONFIGURE="$HEAD"'\nexecute_before_dh_auto_configure: cross-tools\n\ncross-tools:\n\tmkdir -p debian/cross-tools\n'
CLEAN="$HEAD"'\nexecute_before_dh_auto_clean: debian-clean\n\trm -f debian/clean.stamp\n\ndebian-clean:\n\trm -rf debian/cross-tools\n'
plain() {  # plain DIR RULES: a plain source tree with a C file the projection would change
	local d=$1
	mkdir -p "$d/debian/source" "$d/src"
	printf '/* a comment */\nint main(void) { return 0; }\n' > "$d/src/a.c"
	printf '/* a header the scanner reads */\nint f(void);\n' > "$d/src/a.h"
	printf '3.0 (quilt)\n' > "$d/debian/source/format"
	printf 'Source: fixture\nSection: misc\nPriority: optional\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nBuild-Depends: debhelper-compat (= 13)\nStandards-Version: 4.7.0\n\nPackage: fixture\nArchitecture: any\nDescription: fixture\n fixture for the plain-from-lc kept-hook test\n' > "$d/debian/control"
	printf "$2" > "$d/debian/rules"; chmod +x "$d/debian/rules"
	printf 'Files: *\nCopyright: 2026 Daniel Campos Ramos\nLicense: GPL-3+\n' > "$d/debian/copyright"
	printf 'fixture (1.0-1) unstable; urgency=medium\n\n  * Fixture.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 +0000\n' > "$d/debian/changelog"
}
prepare() {  # prepare DIR [debian_prepare args]
	local d=$1; shift
	(cd "$d" && PYTHONPATH="$OS" python3 -m lean.debian_prepare "$d" 1.0-1+lc1 --toolkit "$OS" "$@" >"$T/prep.log" 2>&1) || { cat "$T/prep.log"; return 1; }
}

# round trip: CASE RULES PLAN(yes|no)
round() {
	local c=$1 rules=$2 plan=$3 args=() pfl=(--drop-plan) pp=()
	[ "$plan" = yes ] && args=(--preserve-source 'src/*.h' 'g-ir-scanner reads it') && pfl=(--save-plan "$T/$c-plan.json") && pp=(--preserve-plan "$T/$c-plan.json")
	mkdir -p "$T/$c" && plain "$T/$c/orig" "$rules" || return 1
	cp -a "$T/$c/orig" "$T/$c/lc" && prepare "$T/$c/lc" "${args[@]}" || { bad "$c: debian_prepare failed"; return 1; }
	cp -a "$T/$c/lc" "$T/$c/back"
	if ! python3 "$PFL" "${pfl[@]}" "$T/$c/back" >"$T/$c.pfl.log" 2>&1; then bad "$c: plain-from-lc.py failed: $(tail -1 "$T/$c.pfl.log")"; return 1; fi
	[ "$(treehash "$T/$c/back")" = "$(treehash "$T/$c/orig")" ] && ok "$c: plain-from-lc.py gives the plain tree back byte for byte" \
		|| { bad "$c: the plain tree differs: $(diff -r "$T/$c/orig" "$T/$c/back" | head -3)"; return 1; }
	prepare "$T/$c/back" "${pp[@]}" || { bad "$c: debian_prepare on the plain tree failed"; return 1; }
	[ "$(treehash "$T/$c/back")" = "$(treehash "$T/$c/lc")" ] && ok "$c: the step on it gives the same +lc1 tree byte for byte" \
		|| bad "$c: the second +lc1 tree differs: $(diff -r "$T/$c/lc" "$T/$c/back" | head -3)"
}
round configure "$CONFIGURE" no
round clean "$CLEAN" no
round configure-plan "$CONFIGURE" yes
round none "$HEAD" no

# a kept-hook tail edited by hand is not what the step writes: stop, tree untouched
rm -rf "$T/e" && cp -a "$T/configure/lc" "$T/e" && sed -i 's/^execute_before_dh_auto_configure: .WAIT sparky-lean-source-project$/execute_before_dh_auto_configure: sparky-lean-source-project/' "$T/e/debian/rules"
before=$(treehash "$T/e")
if python3 "$PFL" --drop-plan "$T/e" >"$T/e.log" 2>&1; then bad "an edited kept-hook tail was taken for the step's"; else
	grep -q 'the rules file does not end with the lc1 targets' "$T/e.log" && [ "$(treehash "$T/e")" = "$before" ] \
		&& ok "an edited kept-hook tail stops with the rules message and the tree is left as it was" || bad "edited tail: $(tail -1 "$T/e.log")"
fi

# red: plain-from-lc.py before ORDER 768b stops on the kept form
ROOT=$(cd "$OS/.." && pwd)
if git -C "$ROOT" cat-file -e 665fd06a00:sparky-os/repo/plain-from-lc.py 2>/dev/null; then
	git -C "$ROOT" show 665fd06a00:sparky-os/repo/plain-from-lc.py > "$T/old-pfl.py"
	rm -rf "$T/r" && cp -a "$T/configure/lc" "$T/r"
	if python3 "$T/old-pfl.py" --drop-plan "$T/r" >"$T/r.log" 2>&1; then bad "red: the old plain-from-lc.py took the kept form"; else
		grep -q 'the rules file does not end with the lc1 targets' "$T/r.log" && ok "red: the old plain-from-lc.py stops on the kept form" || bad "red: $(tail -1 "$T/r.log")"
	fi
else
	echo "skip red (the checkout lacks commit 665fd06a00)"
fi
[ $fail = 0 ] && echo "PASS plain-from-lc kept hooks" || echo "FAILED plain-from-lc kept hooks"
exit $fail
