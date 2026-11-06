#!/bin/bash
# ORDER 421: a source package made from a recipe is the same bytes whatever the clock, the zone, the umask and the checkout time.
# Makes a small published +lc1 fixture source, then its successor (repo/lc-successor.py) three times under different time zones,
# umasks, checkout times and (with faketime installed) clocks, and fails on any difference in the .dsc or the .debian.tar.xz.
# Also: the recipe date comes from SOURCE_DATE_EPOCH or a committed recipe, never from the clock (repo/reproducible.py), and a
# broken copy of the packer (no normalization) is caught, so this test can fail.
# (faketime moves stat() times too unless NO_FAKE_STAT=1; the test sets it, as the checkout times are real files.)
# Needs dpkg-dev, devscripts (dch), python3, perl, git, xz; run it in a container, not on the desktop.
# Usage: bash test.sh [SPARKY_OS_DIR]     (the tree under test, default: this one)
set -uo pipefail
OS=$(cd "${1:-$(dirname "$0")/../..}" && pwd)
T=$(mktemp -d)
trap 'chmod -R u+rwx "$T"; rm -rf "$T"' EXIT
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com PYTHONDONTWRITEBYTECODE=1 LC_ALL=C.UTF-8
unset SOURCE_DATE_EPOCH
STAMP=1793974631
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

# the fixture: a published +lc1 source (upstream tarball, debian/ with the Lean Code toolkit), dated by its recipe
mkdir -p "$T/up/fixture-1.0" "$T/pub"
printf '#!/bin/sh\necho hello\n' > "$T/up/fixture-1.0/hello.sh"
tar -C "$T/up" --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf - fixture-1.0 | xz -9 > "$T/pub/fixture_1.0.orig.tar.xz"
cp -r "$T/up/fixture-1.0" "$T/tree"
mkdir -p "$T/tree/debian/source"
printf '3.0 (quilt)\n' > "$T/tree/debian/source/format"
printf '\0\1\2 a binary file that travels in the Debian tarball\n' > "$T/tree/data.bin"
printf 'data.bin\n' > "$T/tree/debian/source/include-binaries"
printf 'Source: fixture\nSection: misc\nPriority: optional\nMaintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nBuild-Depends: debhelper-compat (= 13)\nStandards-Version: 4.7.0\n\nPackage: fixture\nArchitecture: all\nDescription: fixture\n fixture for the reproducible source test\n' > "$T/tree/debian/control"
printf '#!/usr/bin/make -f\n%%:\n\tdh $@\n' > "$T/tree/debian/rules"; chmod +x "$T/tree/debian/rules"
printf 'Files: *\nCopyright: 2026 Daniel Campos Ramos\nLicense: GPL-3+\n' > "$T/tree/debian/copyright"
printf 'fixture (1.0-1) unstable; urgency=medium\n\n  * Fixture.\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  Mon, 02 Nov 2026 12:00:00 +0000\n' > "$T/tree/debian/changelog"
if ! (cd "$T/tree" && SOURCE_DATE_EPOCH=$STAMP PYTHONPATH="$OS" python3 -m lean.debian_prepare "$T/tree" 1.0-1+lc1 --toolkit "$OS" >"$T/prep.log" 2>&1); then
	cat "$T/prep.log"; bad "fixture: debian_prepare failed"; exit 1
fi
grep -q "SOURCE_DATE_EPOCH is not set" "$T/prep.log" && bad "debian_prepare warned about the clock although SOURCE_DATE_EPOCH was set"
python3 "$OS/repo/reproducible.py" normalize-tree $STAMP "$T/tree"
mv "$T/tree" "$T/pub/fixture-1.0"
(cd "$T/pub" && SOURCE_DATE_EPOCH=$STAMP dpkg-source -b fixture-1.0 >/dev/null 2>&1) || { bad "fixture: dpkg-source -b failed"; exit 1; }
ls "$T/pub"/*.dsc >/dev/null || exit 1
trailer=$(sed -n 's/^ -- [^>]*>  //p' "$T/pub/fixture-1.0/debian/changelog" | head -1)
[ "$trailer" = "$(python3 "$OS/repo/reproducible.py" rfc2822 $STAMP)" ] && ok "debian_prepare dates its changelog entry by SOURCE_DATE_EPOCH (UTC): $trailer" || bad "debian_prepare entry date is '$trailer'"

successor() {  # successor TOOLTREE ID TZ UMASK TOUCHDATE [prefix command...]
	local tool=$1 id=$2 tz=$3 um=$4 td=$5; shift 5
	rm -rf "$T/in-$id" "$T/w-$id" "$T/out-$id"; mkdir -p "$T/in-$id" "$T/w-$id"
	cp "$T"/pub/*.dsc "$T"/pub/*.tar.xz "$T/in-$id/"
	touch -d "$td" "$T/in-$id"/*
	(umask "$um"; export TZ=$tz; "$@" python3 "$tool/repo/lc-successor.py" --source-date-epoch $STAMP --work "$T/w-$id" \
		--next 1.0-2 --item 'Packaging revision 2, no source change.' "$T/in-$id/fixture_1.0-1+lc1.dsc" "$T/out-$id" >"$T/log-$id" 2>&1)
}
same() {  # same IDA IDB : the .dsc and .debian.tar.xz are byte for byte the same
	local a=$1 b=$2 f s=0
	for f in fixture_1.0-2+lc1.dsc fixture_1.0-2+lc1.debian.tar.xz; do
		cmp -s "$T/out-$a/$f" "$T/out-$b/$f" || s=1
	done
	return $s
}
run_three() {  # run_three TOOLTREE -> sets sums
	successor "$1" a America/Sao_Paulo 022 '2026-11-06 10:00:00' || return 1
	sleep 2
	successor "$1" b Asia/Tokyo 077 '2026-11-19 01:00:00' || return 1
	if command -v faketime >/dev/null; then
		successor "$1" c Pacific/Auckland 002 "2025-01-01 00:00:00" env NO_FAKE_STAT=1 faketime -f '@2027-03-01 23:59:50' || return 1
	else
		successor "$1" c Pacific/Auckland 002 '2025-01-01 00:00:00' || return 1
	fi
}

if run_three "$OS"; then
	same a b && same a c && ok "three successors (3 zones, 3 umasks, 3 checkout times$(command -v faketime >/dev/null && echo ', 3 clocks')) are byte-identical: $(sha256sum < "$T/out-a/fixture_1.0-2+lc1.debian.tar.xz" | cut -c1-16) $(sha256sum < "$T/out-a/fixture_1.0-2+lc1.dsc" | cut -c1-16)" || bad "successors differ between runs"
	d=$(sed -n 's/^ -- [^>]*>  //p' "$T/out-a/fixture_1.0-2+lc1.changelog" | head -2 | tr '\n' '|')
	[ "$d" = "$(python3 "$OS/repo/reproducible.py" rfc2822 $STAMP)|$(python3 "$OS/repo/reproducible.py" rfc2822 $STAMP)|" ] && ok "both new changelog entries carry the recipe date" || bad "entry dates: $d"
	tar -tf "$T/out-a/fixture_1.0-2+lc1.debian.tar.xz" | grep -qx data.bin && ok "the include-binaries file travels in the Debian tarball (and is covered)" || bad "data.bin is not in the Debian tarball"
	tar -tvf "$T/out-a/fixture_1.0-2+lc1.debian.tar.xz" --full-time | awk '{print $4" "$5}' | sort -u > "$T/times"
	[ "$(wc -l < "$T/times")" -eq 1 ] && grep -q '^2026-11-06 14:17:11' "$T/times" && ok "every tar member has the recipe time" || bad "tar times: $(cat "$T/times" | head -3)"
	tar -tvf "$T/out-a/fixture_1.0-2+lc1.debian.tar.xz" | awk '{print $1}' | grep -qvE '^d.........$|^-rw-r--r--$|^-rwxr-xr-x$' && bad "unexpected modes in the tar" || ok "modes are 0644, 0755 or directories"
else
	cat "$T"/log-*; bad "successor failed"
fi

# no recipe date: the tool stops and says so (no fallback to the clock)
if (cd "$T" && python3 "$OS/repo/lc-successor.py" --next 1.0-2 --item x "$T/in-a/fixture_1.0-1+lc1.dsc" "$T/out-none" >"$T/none.log" 2>&1); then
	bad "lc-successor ran without a recipe date"
else
	grep -q "no recipe date" "$T/none.log" && ok "no date: lc-successor stops and says why" || bad "no-date message: $(tail -1 "$T/none.log")"
fi

# a committed recipe has a date (the last commit that touched it); an uncommitted one has none
mkdir "$T/g" && cd "$T/g" && git init -q . && mkdir recipe && echo one > recipe/a
git add recipe && GIT_COMMITTER_DATE='2026-10-01T10:00:00+0000' GIT_AUTHOR_DATE='2026-10-01T10:00:00+0000' git -c user.name=t -c user.email=t@example.org commit -q -m one
echo other > unrelated && git add unrelated && GIT_COMMITTER_DATE='2026-10-09T10:00:00+0000' git -c user.name=t -c user.email=t@example.org commit -q -m two
[ "$(python3 "$OS/repo/reproducible.py" epoch "$T/g/recipe")" = "$(date -u -d '2026-10-01 10:00:00' +%s)" ] && ok "recipe date = committer date of the last commit that touched the recipe" || bad "recipe date from git"
echo two >> recipe/a
python3 "$OS/repo/reproducible.py" epoch "$T/g/recipe" >/dev/null 2>&1 && bad "an uncommitted recipe got a date" || ok "an uncommitted recipe has no date"
SOURCE_DATE_EPOCH=$STAMP python3 "$OS/repo/reproducible.py" epoch "$T/g/recipe" | grep -qx $STAMP && ok "SOURCE_DATE_EPOCH names the date explicitly" || bad "SOURCE_DATE_EPOCH"
cd "$T"

# red: the packer without its normalization must give different bytes under these runs
cp -r "$OS" "$T/broken"
python3 - "$T/broken/repo/reproducible.py" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1]); s = p.read_text()
a = "    normalize_tree(Path(workdir) / tree, stamp)\n"
b = "    return subprocess.run(['dpkg-source', '-b', tree], cwd=workdir, check=True, **kw)\n"
assert a in s
s = s.replace(a, '').replace("    env = {**os.environ, 'SOURCE_DATE_EPOCH': str(stamp)}\n    return subprocess.run(['dpkg-source', '-b', tree], cwd=workdir, check=True, env=env, **kw)\n", b)
p.write_text(s)
PY
rm -rf "$T"/out-*
if run_three "$T/broken"; then
	same a b && same a c && bad "red: the broken packer still gave identical bytes, so this test cannot fail" || ok "red: a packer without normalization gives different bytes (the test can fail)"
else
	cat "$T"/log-*; bad "red run failed to run"
fi
[ $fail = 0 ] && echo "PASS reproducible sources" || echo "FAILED"
exit $fail
