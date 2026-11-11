#!/bin/bash
# ORDER 435: every route from a published +lc1 source back to a plain one keeps the source's Lean Code preserve plan
# (debian/sparky-lean-preserve.json), fixed once in the shared tools; plain-from-lc.py is atomic.
# ORDER 433 found transition-rebuilds dropping the plan because plain-from-lc.py deletes it under every option. Now:
# - plain-from-lc.py stops (touching nothing) on a source with a plan unless the caller says --save-plan FILE or --drop-plan;
# - --save-plan FILE keeps the plan byte for byte, lean.debian_prepare --preserve-plan FILE gives it back to the next source and
#   stops, naming the source, when it cannot be carried unchanged; repo/lc-successor.py uses the same two options;
# - when any option's check fails the tree is left exactly as it was;
# - check_producers.py names a script that calls plain-from-lc.py without choosing, or saves a plan it never hands back.
# Red: the plain-from-lc.py of ORDER 433's main (git object df413e35, when the checkout has it) drops the plan silently and
# changes the tree before an option fails; a producers copy without the choice is named.
# Needs dpkg-dev, devscripts (dch), python3, git, xz; run it in a container, not on the desktop.
# Usage: bash plain-preserve.sh [SPARKY_OS_DIR]
set -uo pipefail
OS=$(cd "${1:-$(dirname "$0")/../..}" && pwd)
T=$(mktemp -d)
trap 'chmod -R u+rwx "$T"; rm -rf "$T"' EXIT
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com PYTHONDONTWRITEBYTECODE=1 LC_ALL=C.UTF-8
STAMP=1793974631
export SOURCE_DATE_EPOCH=$STAMP
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
PFL="$OS/repo/plain-from-lc.py"
treehash() { (cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1); }

# a published +lc1 source tree: MODE none | canonical (two-pattern plan) | indented (a plan in a form debian_prepare does not write)
tree() {  # tree DIR MODE
	local d=$1 mode=$2 args=()
	mkdir -p "$d/debian/source" && printf '#!/bin/sh\necho hello\n' > "$d/hello.sh"
	printf '3.0 (quilt)\n' > "$d/debian/source/format"
	printf 'Source: fixture\nSection: misc\nPriority: optional\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nBuild-Depends: debhelper-compat (= 13)\nStandards-Version: 4.7.0\n\nPackage: fixture\nArchitecture: all\nDescription: fixture\n fixture for the plain-from-lc preserve test\n' > "$d/debian/control"
	printf '#!/usr/bin/make -f\n%%:\n\tdh $@\n' > "$d/debian/rules"; chmod +x "$d/debian/rules"
	printf 'Files: *\nCopyright: 2026 Daniel Campos Ramos\nLicense: GPL-3+\n' > "$d/debian/copyright"
	printf 'fixture (1.0-1) unstable; urgency=medium\n\n  * Fixture.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 +0000\n' > "$d/debian/changelog"
	[ "$mode" = none ] || args=(--preserve-source 'src/*_p.h' 'a tool reads the private-header warning comments' --preserve-source 'tests/*' 'test inputs include deliberate comment fixtures')
	(cd "$d" && PYTHONPATH="$OS" python3 -m lean.debian_prepare "$d" 1.0-1+lc1 --toolkit "$OS" "${args[@]}" >"$d/../prep.log" 2>&1) || { cat "$d/../prep.log"; bad "fixture $mode: debian_prepare failed"; return 1; }
	[ "$mode" != indented ] || python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); open(p,"w").write(json.dumps(d, indent=4)+"\n")' "$d/debian/sparky-lean-preserve.json"
}
mkdir -p "$T/good" "$T/none" "$T/indented"
tree "$T/good/t" canonical && tree "$T/none/t" none && tree "$T/indented/t" indented || exit 1
PLAN_BYTES=$(sha256sum < "$T/good/t/debian/sparky-lean-preserve.json")
fresh() { rm -rf "$T/w"; mkdir "$T/w"; cp -a "$T/$1/t" "$T/w/t"; }

# 1. a source with a plan and no choice: stop, name the way, change nothing
fresh good; before=$(treehash "$T/w/t")
if python3 "$PFL" "$T/w/t" >"$T/g.log" 2>&1; then bad "plain-from-lc.py dropped a plan without being told"; else
	grep -q -- '--save-plan' "$T/g.log" && grep -q -- '--drop-plan' "$T/g.log" && [ "$(treehash "$T/w/t")" = "$before" ] \
		&& ok "a source with a plan and no choice stops, names --save-plan and --drop-plan, and is left as it was" || bad "guard: $(tail -2 "$T/g.log")"
fi

# 2. --save-plan: the plan byte for byte, the tree plain; a stale file is refused
fresh good
if python3 "$PFL" --save-plan "$T/saved.json" "$T/w/t" >"$T/s.log" 2>&1; then
	{ [ "$(sha256sum < "$T/saved.json")" = "$PLAN_BYTES" ] && [ ! -e "$T/w/t/debian/sparky-lean-preserve.json" ] && [ ! -e "$T/w/t/debian/sparky-lean-toolkit" ] \
		&& [ "$(sed -n 1p "$T/w/t/debian/changelog")" = 'fixture (1.0-1) unstable; urgency=medium' ]; } \
		&& ok "--save-plan keeps the plan byte for byte and the tree is plain" || bad "--save-plan result"
else cat "$T/s.log"; bad "--save-plan failed"; fi
fresh good; before=$(treehash "$T/w/t")
if python3 "$PFL" --save-plan "$T/saved.json" "$T/w/t" >"$T/s2.log" 2>&1; then bad "a plan file of an earlier run was overwritten"; else
	[ "$(treehash "$T/w/t")" = "$before" ] && ok "--save-plan refuses an existing file and leaves the tree as it was" || bad "stale plan file left the tree changed"
fi

# 3. no plan: no choice needed, no file written
fresh none
if python3 "$PFL" "$T/w/t" >/dev/null 2>&1 && [ ! -e "$T/w/t/debian/sparky-lean-toolkit" ]; then ok "a source without a plan needs no choice"; else bad "no-plan source"; fi
fresh none
if python3 "$PFL" --save-plan "$T/none-plan.json" "$T/w/t" >/dev/null 2>&1 && [ ! -e "$T/none-plan.json" ]; then ok "--save-plan on a source without a plan writes no file"; else bad "no-plan save"; fi

# 4. --drop-plan
fresh good
python3 "$PFL" --drop-plan "$T/w/t" >/dev/null 2>&1 && [ ! -e "$T/w/t/debian/sparky-lean-preserve.json" ] && ok "--drop-plan removes the plan with the rest, by the caller's choice" || bad "--drop-plan"

# 5. atomic: every option whose check fails leaves the tree as it was (the plan, the toolkit and the rules included)
atomic() {  # atomic ID TOOL OPTION...
	local id=$1 tool=$2; shift 2
	fresh good; before=$(treehash "$T/w/t")
	if python3 "$tool" "$@" "$T/w/t" >"$T/a-$id.log" 2>&1; then echo "ran"; else [ "$(treehash "$T/w/t")" = "$before" ] && echo same || echo changed; fi
}
for opt in "--no-build-depends" "--build-depends-at-end" "--edition-entry" "--lc-successor"; do
	r=$(atomic "$opt" "$PFL" --drop-plan $opt)
	[ "$r" = same ] && ok "atomic: $opt on a tree it does not fit stops and leaves it as it was" || bad "atomic: $opt gave '$r': $(tail -2 "$T/a-$opt.log")"
done
# the last check of the default option (the changelog) fails after the control and rules were already worked out
fresh good; printf 'fixture (1.0-1+lc1) unstable; urgency=medium\n\n  * Not the Lean Code entry.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 +0000\n\n' | cat - "$T/w/t/debian/changelog" > "$T/cl" && cp "$T/cl" "$T/w/t/debian/changelog"
before=$(treehash "$T/w/t")
if python3 "$PFL" --drop-plan "$T/w/t" >"$T/a-cl.log" 2>&1; then bad "atomic: a changelog that is not debian_prepare's was accepted"; else
	[ "$(treehash "$T/w/t")" = "$before" ] && ok "atomic: a failing changelog check leaves control, rules, toolkit and plan as they were" || bad "atomic: changelog stop changed the tree"
fi

# 6. lean.debian_prepare --preserve-plan: the next source has the plan byte for byte; extra patterns follow it; a missing file is no plan
carry() {  # carry ID PLANFILE [prepare args] : plain tree from the good source, then prepare 1.0-2+lc1
	local id=$1 plan=$2; shift 2
	fresh good; python3 "$PFL" --save-plan "$T/p-$id.json" "$T/w/t" >/dev/null 2>&1
	printf 'fixture (1.0-2) unstable; urgency=medium\n\n  * Rebuild.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 +0000\n\n' | cat - "$T/w/t/debian/changelog" > "$T/cl" && cp "$T/cl" "$T/w/t/debian/changelog"
	(cd "$T/w/t" && PYTHONPATH="$OS" python3 -m lean.debian_prepare "$T/w/t" 1.0-2+lc1 --toolkit "$OS" --preserve-plan "${plan/@/$T/p-$id.json}" "$@" >"$T/c-$id.log" 2>&1)
}
if carry same @; then cmp -s "$T/w/t/debian/sparky-lean-preserve.json" "$T/good/t/debian/sparky-lean-preserve.json" && ok "debian_prepare --preserve-plan gives the next source the published plan byte for byte" || bad "carried plan differs"; else cat "$T/c-same.log"; bad "carry failed"; fi
if carry extra @ --preserve-source 'docs/*' 'a doc tool reads these comments'; then
	python3 - "$T/w/t/debian/sparky-lean-preserve.json" <<'PY' && ok "--preserve-plan then --preserve-source: the published patterns first, the new one after" || bad "extra pattern order"
import json, sys
d = json.load(open(sys.argv[1])); assert list(d) == ['src/*_p.h', 'tests/*', 'docs/*'], list(d)
PY
else cat "$T/c-extra.log"; bad "carry with an extra pattern failed"; fi
if carry dup @ --preserve-source 'tests/*' 'again'; then bad "a pattern already in the published plan was taken twice"; else ok "a pattern already in the published plan is refused"; fi
if carry nofile "$T/does-not-exist.json"; then [ ! -e "$T/w/t/debian/sparky-lean-preserve.json" ] && ok "a missing plan file is a source without a plan: none appears" || bad "plan appeared from nothing"; else cat "$T/c-nofile.log"; bad "missing file"; fi

# 7. a plan debian_prepare cannot write byte for byte: stop with the source named and the way on, tree untouched
rm -rf "$T/w"; mkdir "$T/w"; cp -a "$T/indented/t" "$T/w/t"; python3 "$PFL" --save-plan "$T/p-ind.json" "$T/w/t" >/dev/null 2>&1
printf 'fixture (1.0-2) unstable; urgency=medium\n\n  * Rebuild.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 +0000\n\n' | cat - "$T/w/t/debian/changelog" > "$T/cl" && cp "$T/cl" "$T/w/t/debian/changelog"
before=$(treehash "$T/w/t")
if (cd "$T/w/t" && PYTHONPATH="$OS" python3 -m lean.debian_prepare "$T/w/t" 1.0-2+lc1 --toolkit "$OS" --preserve-plan "$T/p-ind.json" >"$T/i.log" 2>&1); then bad "a plan that would change was accepted"; else
	grep -q '^fixture 1.0-2: ' "$T/i.log" && grep -q 'lc-successor.py' "$T/i.log" && [ "$(treehash "$T/w/t")" = "$before" ] \
		&& ok "a plan that would change stops debian_prepare with the source named, the tree untouched" || bad "indented stop: $(tail -2 "$T/i.log")"
fi

# 8. repo/lc-successor.py (the same two options): the published plan and one added pattern

rm -rf "$T/pubsrc"; mkdir -p "$T/pubsrc/up/fixture-1.0"; printf '#!/bin/sh\necho hello\n' > "$T/pubsrc/up/fixture-1.0/hello.sh"
tar -C "$T/pubsrc/up" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf - fixture-1.0 | xz -9 > "$T/pubsrc/fixture_1.0.orig.tar.xz"
cp -a "$T/good/t" "$T/pubsrc/fixture-1.0"; cp "$T/pubsrc/up/fixture-1.0/hello.sh" "$T/pubsrc/fixture-1.0/hello.sh"
python3 "$OS/repo/reproducible.py" normalize-tree $STAMP "$T/pubsrc/fixture-1.0"
(cd "$T/pubsrc" && dpkg-source -b fixture-1.0 >/dev/null 2>&1) || bad "fixture: dpkg-source -b failed"
succ() {  # succ ID [lc-successor args]
	local id=$1; shift
	rm -rf "$T/so-$id" "$T/sw-$id"; mkdir -p "$T/sw-$id"
	python3 "$OS/repo/lc-successor.py" --source-date-epoch $STAMP --work "$T/sw-$id" --next 1.0-2 --item 'Packaging revision 2, no source change.' "$@" "$T/pubsrc/fixture_1.0-1+lc1.dsc" "$T/so-$id" >"$T/su-$id.log" 2>&1
}
if succ same; then
	cp "$T/pubsrc/fixture_1.0.orig.tar.xz" "$T/so-same/"; dpkg-source --no-copy -x "$T/so-same/fixture_1.0-2+lc1.dsc" "$T/xs" >/dev/null 2>&1
	cmp -s "$T/xs/debian/sparky-lean-preserve.json" "$T/good/t/debian/sparky-lean-preserve.json" && ok "lc-successor.py keeps the published plan byte for byte" || bad "successor plan differs"
else cat "$T/su-same.log"; bad "lc-successor.py failed on a source with a plan"; fi
if succ extra --preserve 'docs/*' 'a doc tool reads these comments'; then
	cp "$T/pubsrc/fixture_1.0.orig.tar.xz" "$T/so-extra/"; dpkg-source --no-copy -x "$T/so-extra/fixture_1.0-2+lc1.dsc" "$T/xe" >/dev/null 2>&1
	python3 -c 'import json,sys; assert list(json.load(open(sys.argv[1]))) == ["src/*_p.h","tests/*","docs/*"]' "$T/xe/debian/sparky-lean-preserve.json" && ok "lc-successor.py --preserve adds one pattern after the published ones" || bad "successor extra"
else cat "$T/su-extra.log"; bad "lc-successor.py --preserve failed"; fi

# 9. the producers check names a script that forgets the plan; the repository's own scripts are clean
ROOT=$(cd "$OS/.." && pwd)
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	prod=$(python3 "$OS/tests/reproducible-sources/check_producers.py" "$ROOT" 2>&1) && ok "producers: $(head -1 <<<"$prod")" || bad "producers: $prod"
fi
rm -rf "$T/pr" && mkdir -p "$T/pr/sparky-os/packages/x" && (cd "$T/pr" && git init -q . &&
	printf '#!/bin/bash\npython3 "$TOOLKIT/repo/plain-from-lc.py" source\n' > sparky-os/packages/x/forgets.sh &&
	printf '#!/bin/bash\npython3 "$TOOLKIT/repo/plain-from-lc.py" --save-plan "$WORK/p.json" source\npython3 -m lean.debian_prepare x 1\n' > sparky-os/packages/x/saves-only.sh &&
	printf '#!/bin/bash\npython3 "$TOOLKIT/repo/plain-from-lc.py" --save-plan "$WORK/p.json" source\npython3 -m lean.debian_prepare x 1 --preserve-plan "$WORK/p.json"\n' > sparky-os/packages/x/good.sh &&
	git add . && git -c user.name=t -c user.email=t@example.org commit -q -m x)
python3 "$OS/tests/reproducible-sources/check_producers.py" "$T/pr" >"$T/pr.log" 2>&1
{ grep -q 'forgets.sh:2: plain-from-lc.py without --save-plan or --drop-plan' "$T/pr.log" && grep -q 'saves-only.sh:2: --save-plan without --preserve-plan' "$T/pr.log" && ! grep -q 'good.sh' "$T/pr.log"; } \
	&& ok "red: the producers check names a script that forgets the plan and one that saves it and never hands it back, and passes the complete one" || bad "producers red: $(cat "$T/pr.log")"

# 10. red: ORDER 433's plain-from-lc.py (when the checkout has that commit) drops the plan silently and changes the tree before a check fails
if git -C "$ROOT" cat-file -e df413e35:sparky-os/repo/plain-from-lc.py 2>/dev/null; then
	git -C "$ROOT" show df413e35:sparky-os/repo/plain-from-lc.py > "$T/old-pfl.py"
	fresh good
	if python3 "$T/old-pfl.py" "$T/w/t" >/dev/null 2>&1 && [ ! -e "$T/w/t/debian/sparky-lean-preserve.json" ]; then ok "red: the old tool dropped the plan silently, with no way to keep it"; else bad "red: the old tool did not drop the plan, so test 1 cannot fail"; fi
	r=$(atomic old "$T/old-pfl.py" --edition-entry)
	[ "$r" = changed ] && ok "red: the old tool changed the tree before an option's check failed" || bad "red: old atomic gave '$r'"
else
	echo "skip red copies of the old tool (the checkout has no df413e35)"
fi

[ $fail = 0 ] && echo "PASS plain-from-lc preserve" || echo "FAILED"
exit $fail
