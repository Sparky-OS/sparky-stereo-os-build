#!/bin/sh
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# The C and C++ migration of dpkg-stereo 0.1.17 (ORDER 303), as an ordinary user in a disposable dpkg
# root: an older dpkg-stereo projects the headers of the given packages with #line directives; one
# header is then edited by hand and the .deb of HELD is kept out of APT's cache; the new dpkg-stereo runs
# what its postinst runs (--repair-consumers); then HELD's .deb comes back and the migration finishes.
# Programs built against the migrated headers and against the packages' own headers must give the same
# objects, the same preprocessed tokens on the same lines, and line tables (-g -gno-column-info).
# Usage: c-line-breaks-test.sh OLD_SPARKY_OS NEW_SPARKY_OS ROOT HELD DEB...
#   OLD_SPARKY_OS, NEW_SPARKY_OS: sparky-os folders of the two build-tree versions; ROOT: a scratch folder
#   (removed first); HELD: the package whose .deb is held back once; DEB...: the header packages.
set -u
OLD=$1 NEW=$2 R=$3 HELD=$4
shift 4
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
ds() { lib=$1; shift; DPKG_STEREO_LIB=$lib python3 "$lib/packages/dpkg-stereo/bin/dpkg-stereo" --root "$R/root" "$@"; }
stats() {   # handler-c records: files, files holding #line, #line lines, bytes
	python3 - "$R/root" "$R/pristine" <<'EOF'
import os, re, sys, glob
root, pristine = sys.argv[1], sys.argv[2]
line = re.compile(rb'^[ \t]*#[ \t]*line\b', re.M)
n = files = lines = size = authored = 0
for t in glob.glob(os.path.join(root, 'var/lib/dpkg-stereo/records/*.tsv')):
    for row in open(t, encoding='utf-8', errors='surrogateescape'):
        if row.startswith('#'):
            continue
        v = row.rstrip('\n').split('\t')
        if v[7] != 'c':
            continue
        data = open(root + v[0], 'rb').read()
        k = len(line.findall(data))
        n += 1; files += k > 0; lines += k; size += len(data)
        authored += len(line.findall(open(pristine + v[0], 'rb').read()))
print(f'{n} {files} {lines} {size} {authored}')
EOF
}
rm -rf "$R"
mkdir -p "$R/root/var/lib/dpkg/info" "$R/root/var/lib/dpkg/updates" "$R/root/var/cache/apt/archives" "$R/pristine" "$R/held"
touch "$R/root/var/lib/dpkg/status"
dpkg --force-not-root --force-bad-path --force-script-chrootless --force-depends --root="$R/root" -i "$@" \
	> "$R/dpkg.log" 2>&1 || bad "dpkg -i: $(tail -3 "$R/dpkg.log")"
for d in "$@"; do dpkg-deb -x "$d" "$R/pristine"; done
cp "$@" "$R/root/var/cache/apt/archives/"

echo "== the older dpkg-stereo projects the headers"
ds "$OLD" --project > "$R/old.log" 2>&1 || bad "old --project: $(tail -3 "$R/old.log")"
set -- $(stats)
old_n=$1 old_files=$2 old_lines=$3 old_bytes=$4 authored=$5
[ "$old_n" -gt 0 ] && [ "$old_lines" -gt "$authored" ] && ok "older form: $old_n C and C++ files projected, $old_files of them with #line ($old_lines #line lines, $authored in the authored files), $old_bytes bytes" || bad "older form: $old_n $old_files $old_lines"
edited=$(cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' '$8 == "c" {print $1}' | sort | head -1)
printf 'int my_own_change_stays; /* the person'\''s edit */\n' >> "$R/root$edited"
edited_sha=$(sha256sum "$R/root$edited" | cut -d' ' -f1)
mv "$R/root/var/cache/apt/archives/${HELD}_"*.deb "$R/held/"

echo "== the new dpkg-stereo's postinst action, with $HELD's .deb missing"
t0=$(date +%s%N); ds "$NEW" --repair-consumers > "$R/new1.log" 2>&1; rc=$?; t1=$(date +%s%N)
[ $rc = 1 ] && ok "returns 1 while $HELD's originals are missing ($(( (t1 - t0) / 1000000 )) ms): $(grep 'need their package' "$R/new1.log")" || bad "first run rc=$rc: $(tail -3 "$R/new1.log")"
pending=$(grep -vc '^#' "$R/root/var/lib/dpkg-stereo/renderer-migration-c-line-breaks-v1.pending")
held_records=$(cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' -v p="$HELD" '$8 == "c" && $2 == p' | wc -l)
[ "$pending" -gt 0 ] && [ "$pending" = "$held_records" ] && ok "pending: the $pending files of $HELD, no other" || bad "pending $pending, $HELD records $held_records"
[ "$(sha256sum "$R/root$edited" | cut -d' ' -f1)" = "$edited_sha" ] && ok "the edited header stays as the person left it" || bad "the edited header changed"
grep -q "$edited" "$R"/root/var/lib/dpkg-stereo/records/*.tsv && bad "the edited header is still recorded" || ok "the edited header is no longer recorded"
grep -q "^$edited	.*changed since its package installed it" "$R"/root/var/lib/dpkg-stereo/left/*.tsv && ok "listed as left: changed since its package installed it" || bad "the edited header is not listed as left"

echo "== $HELD's .deb is back"
mv "$R/held/"*.deb "$R/root/var/cache/apt/archives/"
t0=$(date +%s%N); ds "$NEW" --repair-consumers > "$R/new2.log" 2>&1; rc=$?; t1=$(date +%s%N)
[ $rc = 0 ] && [ -e "$R/root/var/lib/dpkg-stereo/renderer-migration-c-line-breaks-v1" ] && [ ! -e "$R/root/var/lib/dpkg-stereo/renderer-migration-c-line-breaks-v1.pending" ] && ok "the migration finishes ($(( (t1 - t0) / 1000000 )) ms)" || bad "second run rc=$rc: $(tail -3 "$R/new2.log")"
set -- $(stats)
[ "$3" = "$5" ] && ok "new form: $1 C and C++ files projected, #line lines $3 (as many as the authored files hold: $5), $4 bytes ($old_bytes before)" || bad "new form: $1 files, $3 #line lines, $5 authored"
ds "$NEW" --verify --deep > "$R/verify.log" 2>&1 && ok "verify --deep: $(tail -1 "$R/verify.log")" || bad "verify --deep: $(grep -v '^dpkg-stereo:' "$R/verify.log" | head -5)"
t0=$(date +%s%N); ds "$NEW" --repair-consumers > "$R/new3.log" 2>&1; rc=$?; t1=$(date +%s%N)
[ $rc = 0 ] && [ ! -s "$R/new3.log" ] && ok "a later run stays idle ($(( (t1 - t0) / 1000000 )) ms)" || bad "later run rc=$rc: $(cat "$R/new3.log")"
cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' '$8 == "c" {print $1, $7}' | sort > "$R/c-records.before"
ds "$NEW" --project > "$R/again.log" 2>&1
cat "$R"/root/var/lib/dpkg-stereo/records/*.tsv | awk -F'\t' '$8 == "c" {print $1, $7}' | sort > "$R/c-records.after"
comm -23 "$R/c-records.before" "$R/c-records.after" | grep -q . && bad "a full --project changed migrated files" \
	|| ok "a full --project keeps every migrated file ($(cat "$R/again.log"))"

echo "== programs built against the migrated headers and against the packages' own"
mkdir -p "$R/build"
cat > "$R/build/c.c" <<'EOF'
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
EOF
printf '#include <bits/stdc++.h>\nint main() { std::vector<int> v{3, 1, 2}; std::sort(v.begin(), v.end()); std::cout << v[0] << std::endl; }\n' > "$R/build/all.cc"
G=$(gcc -print-file-name=include)
# one path for both trees: GCC would otherwise print a shorter real path of a system header
I="-fno-canonical-system-headers -nostdinc -isystem $R/build/inc/usr/include/c++/16 -isystem $R/build/inc/usr/include/x86_64-linux-gnu/c++/16 -isystem $G -isystem $R/build/inc/usr/include/x86_64-linux-gnu -isystem $R/build/inc/usr/include"
same=0
for t in pristine root; do
	ln -sfn "../$t" "$R/build/inc"
	(cd "$R/build" && gcc $I -O2 -c c.c -o c-$t.o && gcc $I -O2 -g -gno-column-info -c c.c -o cg-$t.o && gcc $I -E c.c > c-$t.i \
		&& g++ -std=c++23 $I -O2 -c all.cc -o all-$t.o && g++ -std=c++23 $I -O2 -g -gno-column-info -c all.cc -o allg-$t.o \
		&& g++ -std=c++23 $I -E all.cc > all-$t.i) || bad "build against $t"
done
for f in c all; do
	cmp -s "$R/build/$f-pristine.o" "$R/build/$f-root.o" && cmp -s "$R/build/${f}g-pristine.o" "$R/build/${f}g-root.o" && same=$((same + 1)) \
		|| bad "$f: objects differ"
done
[ $same = 2 ] && ok "objects identical, -O2 and -O2 -g -gno-column-info (line tables), C and C++"
DPKG_STEREO_LIB=$NEW python3 - "$R/build" <<'EOF' && ok "preprocessed output: the same tokens on the same lines of the same files" || bad "preprocessed output differs"
import os, sys
sys.path.insert(0, os.environ['DPKG_STEREO_LIB'])
from lean import lang_c
d = sys.argv[1]
for f in ('c', 'all'):
    a = lang_c._located(open(os.path.join(d, f + '-pristine.i')).read())
    b = lang_c._located(open(os.path.join(d, f + '-root.i')).read())
    print(f'{f}: {len(a)} units, {len({u[0] for u in a})} files', file=sys.stderr)
    if a != b:
        sys.exit(1)
EOF
# the control must be able to fail: one empty line less in the migrated zlib.h moves the lines below it
cp -a "$R/root" "$R/moved"
python3 -c 'import sys; p = sys.argv[1]; t = open(p).read(); k = t.index("\n\n"); open(p, "w").write(t[:k] + t[k + 1:])' \
	"$R/moved/usr/include/zlib.h"
ln -sfn ../moved "$R/build/inc"
(cd "$R/build" && gcc $I -O2 -g -gno-column-info -c c.c -o cg-moved.o)
cmp -s "$R/build/cg-pristine.o" "$R/build/cg-moved.o" && bad "control: a moved line went unnoticed" \
	|| ok "control: with one line of zlib.h moved, the line tables differ"
rm -rf "$R/moved"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
