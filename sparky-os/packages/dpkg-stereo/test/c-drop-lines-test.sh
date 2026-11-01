#!/bin/sh
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# The C and C++ migration of dpkg-stereo 0.1.20 (ORDER 334; 0.1.17's was ORDER 303), as an ordinary user in a
# disposable dpkg root: an older dpkg-stereo (0.1.19, every authored line kept; or 0.1.15, #line directives)
# projects the headers of the given packages; one header is then edited by hand and the .deb of HELD is kept
# out of APT's cache; the new dpkg-stereo runs what its postinst runs (--repair-consumers); then HELD's .deb
# comes back and the migration finishes. The migrated headers lose their comment-only lines: no #line, and
# no empty line where a comment was. Programs built against them and against the packages' own headers must
# give the same objects without debug information, the same objects with -g once the debug sections are
# stripped, and the same preprocessed tokens with __LINE__ pinned; every lean code line of one migrated
# header resolves by content to the line the render's own map gives.
# Usage: c-drop-lines-test.sh OLD_SPARKY_OS NEW_SPARKY_OS ROOT HELD DEB...
#   OLD_SPARKY_OS, NEW_SPARKY_OS: sparky-os folders of the two build-tree versions; ROOT: a scratch folder
#   (removed first); HELD: the package whose .deb is held back once; DEB...: the header packages (zlib1g-dev
#   among them: the resolver and the control use zlib.h).
set -u
OLD=$1 NEW=$2 R=$3 HELD=$4
shift 4
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
ds() { lib=$1; shift; DPKG_STEREO_LIB=$lib python3 "$lib/packages/dpkg-stereo/bin/dpkg-stereo" --root "$R/root" "$@"; }
py() { DPKG_STEREO_LIB=$NEW python3 "$R/check.py" "$@"; }
rm -rf "$R"
mkdir -p "$R/root/var/lib/dpkg/info" "$R/root/var/lib/dpkg/updates" "$R/root/var/cache/apt/archives" "$R/pristine" "$R/held"
# the checks, in one file (a heredoc per check would nest inside the callers' own heredocs)
cat > "$R/check.py" <<'PYEOF'
import glob, os, re, sys
sys.path.insert(0, os.environ['DPKG_STEREO_LIB'])
what, root, pristine = sys.argv[1], sys.argv[2], sys.argv[3]


def records():
    for t in glob.glob(os.path.join(root, 'var/lib/dpkg-stereo/records/*.tsv')):
        for row in open(t, encoding='utf-8', errors='surrogateescape'):
            v = row.rstrip('\n').split('\t')
            if not row.startswith('#') and v[7] == 'c':
                yield v[0]


if what == 'stats':        # files, files holding #line, #line lines, bytes, authored #line lines, lines, authored lines
    line = re.compile(rb'^[ \t]*#[ \t]*line\b', re.M)
    n = files = lines = size = authored = nl = anl = 0
    for path in records():
        data, orig = open(root + path, 'rb').read(), open(pristine + path, 'rb').read()
        k = len(line.findall(data))
        n += 1; files += k > 0; lines += k; size += len(data); nl += data.count(b'\n'); anl += orig.count(b'\n')
        authored += len(line.findall(orig))
    print(f'{n} {files} {lines} {size} {authored} {nl} {anl}')
elif what == 'empty':      # no lean file holds more empty lines than its authored file
    worse = [p for p in records() if sum(1 for x in open(root + p, 'rb').read().split(b'\n') if not x.strip())
             > sum(1 for x in open(pristine + p, 'rb').read().split(b'\n') if not x.strip())]
    print(f'{len(worse)} files with more empty lines than their authored text {worse[:3]}', file=sys.stderr)
    sys.exit(1 if worse else 0)
elif what == 'tokens':     # the preprocessed outputs give the same tokens (line markers aside)
    from lean import lang_c
    for f in ('c', 'all'):
        a = lang_c._tokens(open(os.path.join(root, f + '-' + pristine + '.i')).read())
        b = lang_c._tokens(open(os.path.join(root, f + '-root.i')).read())
        print(f'{f}: {len(a)} tokens', file=sys.stderr)
        if a != b:
            sys.exit(1)
elif what == 'resolve':    # every lean code line of one header resolves by content where the render's map says
    from lean import locate, project
    path = sys.argv[4]
    hr, mr = open(pristine + path, 'rb').read(), open(root + path, 'rb').read()
    r = project.project(path, hr, 'zlib1g-dev')
    assert r.lean == mr, 'the installed file is not the current render'
    _, rendered, _ = project.render_text(hr.decode(), r.handler, r.variant or None, 'zlib1g-dev', path)
    L = locate.Locator(hr, mr, path)
    lines = mr.decode().split('\n')
    n = wrong = 0
    for j in range(1, rendered.line_map.mr_line_count + 1):
        want = rendered.line_map.lines[j - 1]
        if want == 0 or not lines[j - 1].strip():
            continue
        n += 1
        wrong += L.find(j).line != want
    print(f'{path}: {n} lean code lines, {wrong} resolved elsewhere', file=sys.stderr)
    sys.exit(1 if wrong or not n else 0)
PYEOF
touch "$R/root/var/lib/dpkg/status"
dpkg --force-not-root --force-bad-path --force-script-chrootless --force-depends --root="$R/root" -i "$@" \
	> "$R/dpkg.log" 2>&1 || bad "dpkg -i: $(tail -3 "$R/dpkg.log")"
for d in "$@"; do dpkg-deb -x "$d" "$R/pristine"; done
cp "$@" "$R/root/var/cache/apt/archives/"

echo "== the older dpkg-stereo projects the headers"
ds "$OLD" --project > "$R/old.log" 2>&1 || bad "old --project: $(tail -3 "$R/old.log")"
set -- $(py stats "$R/root" "$R/pristine")
old_n=$1 old_files=$2 old_lines=$3 old_bytes=$4 authored=$5 old_nl=$6 authored_nl=$7
[ "$old_n" -gt 0 ] && ok "older form: $old_n C and C++ files projected, $old_files of them with #line ($old_lines #line lines, $authored in the authored files), $old_nl lines ($authored_nl authored), $old_bytes bytes" || bad "older form: $old_n $old_files $old_lines"
edited=$(cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' '$8 == "c" {print $1}' | sort | head -1)
printf 'int my_own_change_stays; /* the person'\''s edit */\n' >> "$R/root$edited"
edited_sha=$(sha256sum "$R/root$edited" | cut -d' ' -f1)
mv "$R/root/var/cache/apt/archives/${HELD}_"*.deb "$R/held/"

echo "== the new dpkg-stereo's postinst action, with $HELD's .deb missing"
t0=$(date +%s%N); ds "$NEW" --repair-consumers > "$R/new1.log" 2>&1; rc=$?; t1=$(date +%s%N)
[ $rc = 1 ] && ok "returns 1 while $HELD's originals are missing ($(( (t1 - t0) / 1000000 )) ms): $(grep 'need their package' "$R/new1.log")" || bad "first run rc=$rc: $(tail -3 "$R/new1.log")"
pending=$(grep -vc '^#' "$R/root/var/lib/dpkg-stereo/renderer-migration-c-drop-lines-v2.pending")
held_records=$(cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' -v p="$HELD" '$8 == "c" && $2 == p' | wc -l)
[ "$pending" -gt 0 ] && [ "$pending" = "$held_records" ] && ok "pending: the $pending files of $HELD, no other" || bad "pending $pending, $HELD records $held_records"
[ "$(sha256sum "$R/root$edited" | cut -d' ' -f1)" = "$edited_sha" ] && ok "the edited header stays as the person left it" || bad "the edited header changed"
grep -q "$edited" "$R"/root/var/lib/dpkg-stereo/records/*.tsv && bad "the edited header is still recorded" || ok "the edited header is no longer recorded"
grep -q "^$edited	.*changed since its package installed it" "$R"/root/var/lib/dpkg-stereo/left/*.tsv && ok "listed as left: changed since its package installed it" || bad "the edited header is not listed as left"

echo "== $HELD's .deb is back"
mv "$R/held/"*.deb "$R/root/var/cache/apt/archives/"
t0=$(date +%s%N); ds "$NEW" --repair-consumers > "$R/new2.log" 2>&1; rc=$?; t1=$(date +%s%N)
[ $rc = 0 ] && [ -e "$R/root/var/lib/dpkg-stereo/renderer-migration-c-drop-lines-v2" ] && [ ! -e "$R/root/var/lib/dpkg-stereo/renderer-migration-c-drop-lines-v2.pending" ] && ok "the migration finishes ($(( (t1 - t0) / 1000000 )) ms)" || bad "second run rc=$rc: $(tail -3 "$R/new2.log")"
set -- $(py stats "$R/root" "$R/pristine")
[ "$3" = "$5" ] && [ "$6" -lt "$old_nl" ] && ok "new form: $1 C and C++ files projected, #line lines $3 (as many as the authored files hold: $5), $6 lines ($old_nl before, $7 authored), $4 bytes ($old_bytes before)" || bad "new form: $1 files, $3 #line lines ($5 authored), $6 lines ($old_nl before)"
py empty "$R/root" "$R/pristine" && ok "no lean file holds more empty lines than its authored text: no empty line where a comment was" || bad "an empty line stands where a comment was"
ds "$NEW" --verify --deep > "$R/verify.log" 2>&1 && ok "verify --deep: $(tail -1 "$R/verify.log")" || bad "verify --deep: $(grep -v '^dpkg-stereo:' "$R/verify.log" | head -5)"
t0=$(date +%s%N); ds "$NEW" --repair-consumers > "$R/new3.log" 2>&1; rc=$?; t1=$(date +%s%N)
[ $rc = 0 ] && [ ! -s "$R/new3.log" ] && ok "a later run stays idle ($(( (t1 - t0) / 1000000 )) ms)" || bad "later run rc=$rc: $(cat "$R/new3.log")"
cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' '$8 == "c" {print $1, $7}' | sort > "$R/c-records.before"
ds "$NEW" --project > "$R/again.log" 2>&1
cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' '$8 == "c" {print $1, $7}' | sort > "$R/c-records.after"
comm -23 "$R/c-records.before" "$R/c-records.after" | grep -q . && bad "a full --project changed migrated files" \
	|| ok "a full --project keeps every migrated file ($(cat "$R/again.log"))"
py resolve "$R/root" "$R/pristine" /usr/include/zlib.h && ok "every lean code line of zlib.h resolves by content where the render's map says" \
	|| bad "the content resolver and the render's map disagree on zlib.h"
line=$(grep -n 'ZEXTERN int ZEXPORT deflate OF\|ZEXTERN int ZEXPORT deflate(' "$R/root/usr/include/zlib.h" | head -1 | cut -d: -f1)
want=$(grep -n 'ZEXTERN int ZEXPORT deflate OF\|ZEXTERN int ZEXPORT deflate(' "$R/pristine/usr/include/zlib.h" | head -1 | cut -d: -f1)
got=$(ds "$NEW" --resolve "/usr/include/zlib.h:$line" 2>&1)
[ "${got%% *}" = "/usr/share/doc/zlib1g-dev/hr/usr/include/zlib.h:$want" ] && ok "dpkg-stereo --resolve /usr/include/zlib.h:$line gives the authored line $want" || bad "--resolve: $got (want line $want)"

echo "== programs built against the migrated headers and against the packages' own"
mkdir -p "$R/build"
cat > "$R/build/c.c" <<'CEOF'
#include <assert.h>
#include <crypt.h>
#include <expat.h>
#include <linux/input.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
int main(int argc, char **argv) {
    assert(argc > 0);
    printf("%s %d %d %s\n", zlibVersion(), XML_MAJOR_VERSION, EV_KEY, strerror(argc));
    return (int)sqrt((double)argc) + (int)strlen(argv[0]) % 7;
}
CEOF
printf '#include <bits/stdc++.h>\nint main() { std::vector<int> v{3, 1, 2}; std::sort(v.begin(), v.end()); std::cout << v[0] << std::endl; }\n' > "$R/build/all.cc"
G=$(gcc -print-file-name=include)
# one path for both trees: GCC would otherwise print a shorter real path of a system header
I="-fno-canonical-system-headers -nostdinc -isystem $R/build/inc/usr/include/c++/16 -isystem $R/build/inc/usr/include/x86_64-linux-gnu/c++/16 -isystem $G -isystem $R/build/inc/usr/include/x86_64-linux-gnu -isystem $R/build/inc/usr/include"
PIN="-U__LINE__ -D__LINE__=0 -w"
same=0
for t in pristine root; do
	ln -sfn "../$t" "$R/build/inc"
	(cd "$R/build" && gcc $I -O2 -c c.c -o c-$t.o && gcc $I -O2 -g -c c.c -o cg-$t.o && gcc $I $PIN -E c.c > c-$t.i \
		&& g++ -std=c++23 $I -O2 -c all.cc -o all-$t.o && g++ -std=c++23 $I -O2 -g -c all.cc -o allg-$t.o \
		&& g++ -std=c++23 $I $PIN -E all.cc > all-$t.i) || bad "build against $t"
	for f in cg allg; do objcopy --strip-debug "$R/build/$f-$t.o" "$R/build/$f-$t.nodebug.o"; done
done
for f in c all; do
	cmp -s "$R/build/$f-pristine.o" "$R/build/$f-root.o" && cmp -s "$R/build/${f}g-pristine.nodebug.o" "$R/build/${f}g-root.nodebug.o" \
		&& same=$((same + 1)) || bad "$f: objects differ"
	cmp -s "$R/build/${f}g-pristine.o" "$R/build/${f}g-root.o" && echo "NOTE $f: the -g objects are identical too" \
		|| echo "NOTE $f: the -g objects differ: their line tables name the lean lines"
done
[ $same = 2 ] && ok "objects identical, -O2, and -O2 -g with the debug sections stripped, C and C++"
py tokens "$R/build" pristine && ok "preprocessed output: the same tokens with __LINE__ pinned" || bad "preprocessed output differs"
# the control must be able to fail: one declaration more in the migrated zlib.h
cp -a "$R/root" "$R/moved"
python3 -c 'import sys; p = sys.argv[1]; t = open(p).read(); k = t.index("ZEXTERN "); open(p, "w").write(t[:k] + "int zlib_control_token;\n" + t[k:])' \
	"$R/moved/usr/include/zlib.h"
ln -sfn ../moved "$R/build/inc"
(cd "$R/build" && gcc $I $PIN -E c.c > c-moved.i)
cmp -s "$R/build/c-pristine.i" "$R/build/c-moved.i" && bad "control: a changed token went unnoticed" \
	|| ok "control: with one declaration added to zlib.h, the preprocessed tokens differ"
rm -rf "$R/moved"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
