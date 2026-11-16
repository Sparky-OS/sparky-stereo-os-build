#!/bin/bash
# Phase 1 of run.sh, inside the container: toy packages, a throwaway key, the real publish-tree.sh on a tree without and with a variant.
set -euo pipefail
sh /run/https-only-apt.sh >/dev/null
apt-get -y update >/dev/null 2>&1
apt-get -y install dpkg-dev gnupg python3 xz-utils >/dev/null 2>&1
T=/work/t; rm -rf "$T" /work/scratch; mkdir -p "$T/sparky-os" /work/scratch
cp -r /sparky-os/repo /sparky-os/lean /sparky-os/iso-build "$T/sparky-os/"
rm -rf "$T/sparky-os/repo/tests"
# the test's copy of the Lean Code release gates: the toy archives carry no lc1 proof
printf '%s\n' '# test stub: check-selection and check-link need lc1-marked archives' 'import sys' 'sys.exit(0)' >"$T/sparky-os/lean/release.py"
cp /old-publish-tree.sh "$T/sparky-os/repo/publish-tree-old.sh"
failed=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; failed=1; }
mk() { # name version arch variant text
	local d=$T/pkg-$1-$3${4:+-$4}
	mkdir -p "$d/DEBIAN" "$d/usr/bin"
	{ printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: test <test@example.invalid>\nDescription: toy %s\n' "$1" "$2" "$3" "$1"
	  [ -z "$4" ] || printf 'Architecture-Variant: %s\n' "$4"; } >"$d/DEBIAN/control"
	printf '#!/bin/sh\necho "%s"\n' "$5" >"$d/usr/bin/$1"; chmod 755 "$d/usr/bin/$1"
	dpkg-deb --root-owner-group -b "$d" "$6" >/dev/null
}
S1=$T/src1; S2=$T/src2; mkdir -p "$S1" "$S2"
mk a 1.0 amd64 '' "a built for baseline" "$S1/a_1.0_amd64.deb"
mk b 1.0 amd64 '' "b built for baseline" "$S1/b_1.0_amd64.deb"
mk c 1.0 all '' "c, architecture all" "$S1/c_1.0_all.deb"
cp "$S1"/*.deb "$S2/"
mk a 1.0 amd64 amd64v3 "a built for x86-64-v3" "$S2/a_1.0_amd64v3.deb"
export GNUPGHOME=/work/gnupg; rm -rf "$GNUPGHOME"; mkdir -m 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key 'test <test@example.invalid>' default default never >/dev/null 2>&1
FPR=$(gpg --with-colons --list-secret-keys | awk -F: '/^fpr:/ {print $10; exit}')
export SPARKY_REPO_KEY=$FPR SPARKY_REPO_GNUPGHOME=$GNUPGHOME SPARKY_APPSTREAM=0 SPARKY_INSTALLABLE=off SPARKY_SCRATCH=/work/scratch TMPDIR=/work/scratch
pub() { # script src dest
	bash "$T/sparky-os/repo/$1" "$2" "$3" >"$3.log" 2>&1 || { echo "publish failed: $1"; tail -20 "$3.log"; return 1; }
}
cmpdir() { diff -r -x InRelease -x Release.gpg -x Release -x '*.log' "$1" "$2" >/dev/null; }
rel() { grep -v '^Date: ' "$1/dists/mashtabba/Release"; }
echo '== a tree with no variant build publishes what the script of main publishes'
pub publish-tree-old.sh "$S1" "$T/old1" && pub publish-tree.sh "$S1" "$T/new1" || exit 1
if cmpdir "$T/old1" "$T/new1" && [ "$(rel $T/old1)" = "$(rel $T/new1)" ]; then ok 'every index, the pool, by-hash and Release (but its date) are byte-identical'; else bad 'the no-variant tree differs'; diff -r -x InRelease -x Release.gpg -x Release "$T/old1" "$T/new1" | head; fi
grep -q '^Architectures: amd64 all$' "$T/new1/dists/mashtabba/Release" && [ ! -e "$T/new1/dists/mashtabba/main/binary-amd64v3" ] && ok 'no amd64v3 in Release, no binary-amd64v3 directory' || bad 'amd64v3 appeared without a variant build'
echo '== a tree with a variant build'
pub publish-tree.sh "$S2" "$T/new2" || exit 1
D=$T/new2/dists/mashtabba
grep -q '^Architectures: amd64 all amd64v3$' "$D/Release" && ok 'Release lists amd64v3' || bad "Architectures: $(grep ^Architectures $D/Release)"
grep -q 'main/binary-amd64v3/Packages$' "$D/Release" && grep -q 'main/binary-amd64v3/Packages.xz$' "$D/Release" && ok 'Release lists the variant index with its compressed copies' || bad 'variant index not in Release'
names() { awk -v RS= '/^Package: / {sub(/^Package: /,""); sub(/\n.*/,""); print}' "$1" | sort | tr '\n' ' '; }
[ "$(names $D/main/binary-amd64/Packages)" = 'a b ' ] && ! grep -q Architecture-Variant "$D/main/binary-amd64/Packages" && grep -q 'Filename: .*/a_1.0_amd64.deb' "$D/main/binary-amd64/Packages" && ok 'binary-amd64 lists the baseline a and b only' || bad "binary-amd64: $(names $D/main/binary-amd64/Packages)"
[ "$(names $D/main/binary-amd64v3/Packages)" = 'a b ' ] && grep -q 'Filename: .*/a_1.0_amd64v3.deb' "$D/main/binary-amd64v3/Packages" && grep -q '^Architecture-Variant: amd64v3' "$D/main/binary-amd64v3/Packages" && [ "$(grep -c '^Package: a$' $D/main/binary-amd64v3/Packages)" = 1 ] && ok 'binary-amd64v3 is a complete copy: the v3 build of a replaces the baseline one, b is there, nothing twice' || bad "binary-amd64v3: $(names $D/main/binary-amd64v3/Packages)"
[ "$(names $D/main/binary-all/Packages)" = 'c ' ] && ok 'binary-all lists c' || bad 'binary-all'
grep -q 'a_1.0_amd64v3.deb' "$D/main/Contents-amd64" && bad 'Contents lists the variant build' || ok 'Contents-amd64 lists a once (the variant build adds nothing)'
[ -f "$T/new2/pool/main/a/a/a_1.0_amd64.deb" ] && [ -f "$T/new2/pool/main/a/a/a_1.0_amd64v3.deb" ] && ok 'the pool holds both builds under different names' || bad 'pool'
echo '== red: the script from before the change cannot publish a variant build'
if pub publish-tree-old.sh "$S2" "$T/old2" 2>/dev/null; then bad 'the old script published the variant tree'; else grep -q 'conflicting archives' "$T/old2.log" && ok 'it stops: conflicting archives for a 1.0 amd64 (the two builds share one identity)' || bad "old script failed differently: $(tail -2 $T/old2.log)"; fi
echo '== a variant build that would take the baseline name is refused'
mkdir -p "$T/wrong"; mk a 1.0 amd64 amd64v3 "wrong name" "$T/wrong/a_1.0_amd64.deb"
if pub publish-tree.sh "$T/wrong" "$T/refused" 2>/dev/null; then bad 'a mis-named variant build was published'; else grep -q 'must be named NAME_VERSION_amd64v3.deb' "$T/refused.log" && ok 'refused, naming the rule' || bad "refused for another reason: $(tail -2 $T/refused.log)"; fi
# the incomplete index a naive publisher writes: only the variant builds (the trap apt 3.3.3 showed)
cp -r "$T/new2" "$T/naive"
D=$T/naive/dists/mashtabba; V=$D/main/binary-amd64v3
awk -v RS= -v ORS='\n\n' '/\nArchitecture-Variant: amd64v3/' "$V/Packages" | sed '$d' >"$V/Packages.n"; mv "$V/Packages.n" "$V/Packages"
rm -f "$V"/Packages.gz "$V"/Packages.xz; rm -rf "$V/by-hash"
python3 - "$D" <<'PYEOF'
import hashlib, os, sys
d = sys.argv[1]
lines = ['Origin: Sparky Stereo OS', 'Suite: testing', 'Codename: mashtabba', 'Architectures: amd64 all amd64v3', 'Components: main', 'SHA256:']
for root, _, files in os.walk(os.path.join(d, 'main')):
    if 'by-hash' in root or 'dep11' in root: continue
    for f in files:
        if f == 'Packages':
            p = os.path.join(root, f); b = open(p, 'rb').read()
            lines.append(' %s %d %s' % (hashlib.sha256(b).hexdigest(), len(b), os.path.relpath(p, d)))
open(os.path.join(d, 'Release'), 'w').write('\n'.join(lines) + '\n')
os.remove(os.path.join(d, 'InRelease')); os.remove(os.path.join(d, 'Release.gpg'))
PYEOF
exit $failed
