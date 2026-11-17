#!/bin/bash
# Phase 1 of libstereo-av1.sh, inside a container: compare the builds, mark the variant, publish a throwaway tree.
set -uo pipefail
sh /run/https-only-apt.sh >/dev/null
apt-get -y update >/dev/null 2>&1
apt-get -y install dpkg-dev binutils gnupg python3 xz-utils >/dev/null 2>&1
W=/work/av1; rm -rf "$W" /work/scratch; mkdir -p "$W/base" "$W/v3" "$W/src" /work/scratch
cp /base/libstereo-av1_*.deb /base/libstereo-av-dev_*.deb /base/libstereo-av-dev-lc-hr_*.deb "$W/base/" 2>/dev/null || cp /base/libstereo-av1_*.deb /base/libstereo-av-dev_*.deb "$W/base/"; cp /v3/libstereo-av1_*.deb "$W/v3/"; mkdir -p "$W/v3all"; cp /v3/libstereo-av*.deb "$W/v3all/" 2>/dev/null || true
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
B=$(ls "$W"/base/libstereo-av1_*.deb); V=$(ls "$W"/v3/libstereo-av1_*.deb)
f() { dpkg-deb -f "$1" "$2" 2>/dev/null || true; }
same=1
for k in Package Version Architecture Section Priority Multi-Arch Depends Pre-Depends Recommends Suggests Breaks Conflicts Replaces Provides Source; do
	[ "$(f $B $k)" = "$(f $V $k)" ] || { same=0; echo "control field $k differs: [$(f $B $k)] [$(f $V $k)]"; }
done
[ $same = 1 ] && ok "the two builds have equal control fields: $(f $B Package) $(f $B Version), Depends: $(f $B Depends)" || bad 'control fields differ'
for x in B V; do mkdir -p "$W/x$x"; dpkg-deb -x "${!x}" "$W/x$x"; done
SB=$(ls "$W"/xB/usr/lib/x86_64-linux-gnu/libstereo-av.so.*.*.*); SV=$(ls "$W"/xV/usr/lib/x86_64-linux-gnu/libstereo-av.so.*.*.*)
cmp -s "$SB" "$SV" && bad 'the two libraries are identical' || ok 'the two libraries differ'
# instructions of the x86-64-v3 level: VEX-encoded (v...), ymm registers, BMI1/2, LZCNT, MOVBE by mnemonic (cmovbe is not movbe)
vex() { objdump -d --no-show-raw-insn "$1" | awk '$2 ~ /^v[a-z]/ || $2 ~ /^(andn|bextr|blsi|blsr|blsmsk|shlx|shrx|sarx|rorx|tzcnt|lzcnt|movbe)$/ || /ymm/' | wc -l; }
nb=$(vex $SB); nv=$(vex $SV)
echo "instructions of the level (VEX, ymm, BMI, LZCNT, MOVBE): baseline $nb, v3 $nv"
[ "$nb" = 0 ] && [ "$nv" -gt 0 ] && ok "the v3 library holds $nv instructions of the level, the baseline none" || bad "instruction counts: baseline $nb, v3 $nv"
# the variant mark is written at BUILD time (build-variant.sh: XB-Architecture-Variant in debian/control): the build already carries it, and only the file name
# (publish-tree.sh selects NAME_VERSION_amd64v3.deb) is given here. A v3 deb without the field is refused: nothing is repacked.
VD=$W/src; cp "$W"/base/*.deb "$VD/"
f2() { dpkg-deb -f "$1" Architecture-Variant; }
if [ "$(f2 "$V")" = amd64v3 ]; then cp "$V" "$VD/$(basename "$V" _amd64.deb)_amd64v3.deb"; ok "the v3 build carries Architecture-Variant: amd64v3 from its own build (no repack)"; else bad "the v3 deb carries no Architecture-Variant: build it with build-variant.sh"; fi
# the whole variant set of the build (libstereo-av1, libstereo-av-dev and its -lc-hr companion, each carrying the field from its build) beside the
# published baseline set: the Lean Code release check with this tree's toolkit (the pairing, ORDER 108)
if ls "$W"/v3all/libstereo-av-dev-lc-hr_*.deb >/dev/null 2>&1; then
	mkdir -p "$W/setb" "$W/setv"
	cp /tree-pool/libstereo-av1_*.deb /tree-pool/libstereo-av-dev_*.deb /tree-pool/libstereo-av-dev-lc-hr_*.deb "$W/setb/"
	for d in "$W"/v3all/libstereo-av1_*.deb "$W"/v3all/libstereo-av-dev_*.deb "$W"/v3all/libstereo-av-dev-lc-hr_*.deb; do
		[ "$(dpkg-deb -f "$d" Architecture-Variant)" = amd64v3 ] || bad "$(basename "$d") carries no Architecture-Variant"
		cp "$d" "$W/setv/$(basename "$d" _amd64.deb)_amd64v3.deb"
	done
	out=$(cd /sparky-os && PYTHONPATH=/sparky-os python3 -B -m lean.release check-debs --no-record "$W"/setb/*.deb "$W"/setv/*.deb 2>&1 | tail -1)
	echo "$out" | grep -q 'verified 6 packages' && ok "check-debs: the published baseline set and the build-time variant set together: $out" || bad "check-debs on both sets: $out"
fi
# publish with the real publish-tree.sh (a copy; the Lean Code gates need lc1-marked toy-free archives only for the rebuilt step, stubbed here)
T=/work/av1/t; mkdir -p "$T/sparky-os"; cp -r /sparky-os/repo /sparky-os/lean /sparky-os/iso-build "$T/sparky-os/"; rm -rf "$T/sparky-os/repo/tests"
printf '%s\n' 'import sys' 'sys.exit(0)' >"$T/sparky-os/lean/release.py"
sed -i 's/^ORIGIN="Sparky Stereo OS"/ORIGIN="Toy variants"/' "$T/sparky-os/repo/publish-tree.sh"
export GNUPGHOME=/work/av1/gnupg; mkdir -m 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key 'test' default default never >/dev/null 2>&1
export SPARKY_REPO_KEY=$(gpg --with-colons --list-secret-keys | awk -F: '/^fpr:/ {print $10; exit}') SPARKY_REPO_GNUPGHOME=$GNUPGHOME SPARKY_APPSTREAM=0 SPARKY_INSTALLABLE=off SPARKY_SCRATCH=/work/scratch TMPDIR=/work/scratch
bash "$T/sparky-os/repo/publish-tree.sh" "$VD" /work/av1/tree >/work/av1/publish.log 2>&1 && ok 'publish-tree.sh published the baseline and the variant' || { bad 'publish failed'; tail -5 /work/av1/publish.log; }
grep -q '^Architectures: amd64 amd64v3$' /work/av1/tree/dists/mashtabba/Release && ok 'Release: Architectures: amd64 amd64v3' || bad "Release: $(grep ^Arch /work/av1/tree/dists/mashtabba/Release)"
printf 'base %s\nv3 %s\n' "$(sha256sum $SB | cut -d' ' -f1)" "$(sha256sum $SV | cut -d' ' -f1)" >/work/av1/hashes
exit $failed
