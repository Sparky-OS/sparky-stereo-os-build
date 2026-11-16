#!/bin/bash
# Phase 1 of libstereo-av1.sh, inside a container: compare the builds, mark the variant, publish a throwaway tree.
set -uo pipefail
sh /run/https-only-apt.sh >/dev/null
apt-get -y update >/dev/null 2>&1
apt-get -y install dpkg-dev binutils gnupg python3 xz-utils >/dev/null 2>&1
W=/work/av1; rm -rf "$W" /work/scratch; mkdir -p "$W/base" "$W/v3" "$W/src" /work/scratch
cp /base/libstereo-av1_*.deb /base/libstereo-av-dev_*.deb "$W/base/"; cp /v3/libstereo-av1_*.deb "$W/v3/"
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
# the variant mark: Architecture-Variant in the control and the file name (publish-tree.sh selects by it)
VM=$W/mark; rm -rf "$VM"; dpkg-deb -R "$V" "$VM"; printf 'Architecture-Variant: amd64v3\n' >>"$VM/DEBIAN/control"
VD=$W/src; cp "$W"/base/*.deb "$VD/"
dpkg-deb --root-owner-group -b "$VM" "$VD/$(basename "$V" _amd64.deb)_amd64v3.deb" >/dev/null
f2() { dpkg-deb -f "$1" Architecture-Variant; }
[ "$(f2 $VD/*_amd64v3.deb)" = amd64v3 ] && ok 'the v3 build is marked Architecture-Variant: amd64v3 and named _amd64v3.deb' || bad 'mark'
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
