#!/bin/bash
# ORDER 421: a source package made from a recipe is the same bytes whatever the clock, the zone, the umask and the checkout time.
# Makes a small published +lc1 fixture source, then its successor (repo/lc-successor.py) three times under different time zones,
# umasks, checkout times and (with faketime installed) clocks, and fails on any difference in the .dsc or the .debian.tar.xz.
# Also: the recipe date comes from SOURCE_DATE_EPOCH or a committed recipe, never from the clock (repo/reproducible.py), and a
# broken copy of the packer (no normalization) is caught, so this test can fail.
# ORDER 421b: lean.debian_prepare stops without a date (red), sparky_provenance_init gives every build its recipe date and the
# container arguments (repo/build-provenance.sh), and no script that writes a source reads the clock or packs an unnormalized
# tree (check_producers.py, with a red copy).
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
# red (ORDER 421b): without a date debian_prepare stops, says what to set, and touches nothing
if (cd "$T/tree" && env -u SOURCE_DATE_EPOCH PYTHONPATH="$OS" python3 -m lean.debian_prepare "$T/tree" 1.0-1+lc1 --toolkit "$OS" >"$T/nodate.log" 2>&1); then
	bad "debian_prepare ran without SOURCE_DATE_EPOCH"
else
	grep -q 'SOURCE_DATE_EPOCH is not set' "$T/nodate.log" && grep -q 'reproducible.py epoch' "$T/nodate.log" && [ ! -e "$T/tree/debian/sparky-lean-toolkit" ] && ok "debian_prepare without a date stops, names the remedy and leaves the tree as it was" || bad "no-date stop: $(tail -2 "$T/nodate.log")"
fi
if ! (cd "$T/tree" && SOURCE_DATE_EPOCH=$STAMP PYTHONPATH="$OS" python3 -m lean.debian_prepare "$T/tree" 1.0-1+lc1 --toolkit "$OS" >"$T/prep.log" 2>&1); then
	cat "$T/prep.log"; bad "fixture: debian_prepare failed"; exit 1
fi
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
# ORDER 421b: the engine step. A build script that calls sparky_provenance_init gets its recipe's date (SOURCE_DATE_EPOCH, else the
# last commit touching the script's folder, clean tree), the changelog date in UTC, and the container arguments carrying both and
# reproducible.py; with no date it stops (return 1) and says why.
E=$T/engine; mkdir -p "$E/sparky-os/repo" "$E/sparky-os/packages/demo" "$E/sparky-os/packages/other"
cp "$OS/repo/build-provenance.sh" "$OS/repo/reproducible.py" "$E/sparky-os/repo/"
cat > "$E/sparky-os/packages/demo/build.sh" <<'DEMO'
#!/bin/bash
set -euo pipefail
. "$(dirname "$0")/../../repo/build-provenance.sh"
sparky_provenance_init no-such-image:0
echo "EPOCH=$SOURCE_DATE_EPOCH"
echo "RFC=$SOURCE_DATE_RFC2822"
printf 'ARG %s\n' "${SPARKY_PROV_ARGS[@]}"
DEMO
echo a > "$E/sparky-os/packages/demo/a"; echo b > "$E/sparky-os/packages/other/b"
(cd "$E" && git init -q . && git add . && GIT_COMMITTER_DATE='2026-10-01T10:00:00+0000' git -c user.name=t -c user.email=t@example.org commit -q -m one &&
	echo c >> sparky-os/packages/other/b && GIT_COMMITTER_DATE='2026-10-09T10:00:00+0000' git -c user.name=t -c user.email=t@example.org commit -q -am two)
want=$(date -u -d '2026-10-01 10:00:00' +%s)
out=$(env -u SOURCE_DATE_EPOCH TZ=Asia/Tokyo bash "$E/sparky-os/packages/demo/build.sh" 2>&1)
grep -qx "EPOCH=$want" <<<"$out" && ok "sparky_provenance_init: the recipe date is the last commit touching the recipe's folder, not the newer commit elsewhere" || bad "engine date: $out"
grep -qx "RFC=Thu, 01 Oct 2026 10:00:00 +0000" <<<"$out" && ok "the changelog date is UTC whatever the zone" || bad "engine rfc: $out"
grep -qx "ARG SOURCE_DATE_EPOCH=$want" <<<"$out" && grep -q "ARG SOURCE_DATE_RFC2822=Thu, 01 Oct 2026" <<<"$out" && grep -q "ARG $E/sparky-os/repo/reproducible.py:/run/reproducible.py:ro" <<<"$out" && grep -q 'ARG SPARKY_SOURCE_DATE_BASIS=the last commit touching sparky-os/packages/demo' <<<"$out" && ok "the container arguments carry the date, its basis and reproducible.py" || bad "engine args: $out"
out=$(SOURCE_DATE_EPOCH=$STAMP bash "$E/sparky-os/packages/demo/build.sh" 2>&1)
grep -qx "EPOCH=$STAMP" <<<"$out" && grep -q 'ARG SPARKY_SOURCE_DATE_BASIS=environment' <<<"$out" && ok "SOURCE_DATE_EPOCH set by the caller wins and the basis says so" || bad "engine env: $out"
echo dirty >> "$E/sparky-os/packages/demo/a"
if out=$(env -u SOURCE_DATE_EPOCH bash "$E/sparky-os/packages/demo/build.sh" 2>&1); then bad "red: a recipe with uncommitted changes got a date: $out"; else
	grep -q 'not committed' <<<"$out" && grep -q 'no source date' <<<"$out" && ok "red: an uncommitted recipe stops the call and names the way out" || bad "dirty message: $out"
fi
# the Python drivers get the same through release/provenance_args.py
if python3 - "$OS" "$E" "$want" <<'PY'
import os, sys
from pathlib import Path
os_dir, e, want = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
sys.path.insert(0, str(os_dir / 'release'))
import provenance_args
provenance_args.SCRIPT = e / 'sparky-os/repo/build-provenance.sh'
os.system('cd %s/sparky-os/packages/demo && git checkout -q a' % e)
os.environ.pop('SOURCE_DATE_EPOCH', None)
words = provenance_args.provenance_args('no-such-image:0', e / 'sparky-os/packages/demo')
assert f'SOURCE_DATE_EPOCH={want}' in words, words
PY
then ok "release/provenance_args.py hands a Python driver the same date"; else bad "provenance_args"; fi

# ORDER 421b: no script that writes a source reads the clock or packs an unnormalized tree; a broken copy is caught
ROOT=$(cd "$OS/.." && pwd)
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
	prod=$(python3 "$OS/tests/reproducible-sources/check_producers.py" "$ROOT" 2>&1) && ok "producers: $(head -1 <<<"$prod")" || bad "producers: $prod"
	rm -rf "$T/pr" && mkdir -p "$T/pr/sparky-os/packages/x" && (cd "$T/pr" && git init -q . &&
		printf '#!/bin/bash\nset -e\ndch --newversion 1-1 "x"\ndpkg-source -b .\n' > sparky-os/packages/x/build.sh && git add . && git -c user.name=t -c user.email=t@example.org commit -q -m x)
	python3 "$OS/tests/reproducible-sources/check_producers.py" "$T/pr" >"$T/pr.log" 2>&1 && bad "red: a producer with a clock-dated dch and an unnormalized pack passed" || { grep -q 'dch without --date' "$T/pr.log" && grep -q 'without normalizing' "$T/pr.log" && ok "red: the producers check names a dch without --date and an unnormalized pack"; } || bad "producers red: $(cat "$T/pr.log")"
else
	echo "skip producers (the tree is not in a git checkout)"
fi

[ $fail = 0 ] && echo "PASS reproducible sources" || echo "FAILED"
exit $fail
