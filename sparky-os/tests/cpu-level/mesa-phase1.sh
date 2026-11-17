#!/bin/bash
# Phase 1 of mesa-apt.sh, inside a container: compare the builds, check both sets together, publish a throwaway tree.
set -uo pipefail
sh /run/https-only-apt.sh >/dev/null
apt-get -y update >/dev/null 2>&1
apt-get -y install dpkg-dev binutils gnupg python3 xz-utils >/dev/null 2>&1
W=/work/mesa; rm -rf "$W" /work/scratch; mkdir -p "$W/base" "$W/v3" "$W/src" /work/scratch
for d in /base/*.deb; do case $d in *-dbgsym_*) ;; *) cp "$d" "$W/base/";; esac; done
for d in /i386/*.deb; do case $d in *-dbgsym_*) ;; *) cp "$d" "$W/src/";; esac; done
for d in /v3/*.deb; do case $d in *-dbgsym_*) ;; *) cp "$d" "$W/v3/$(basename "$d" _amd64.deb)_amd64v3.deb";; esac; done
failed=0; ok() { echo "PASS $*"; }; bad() { echo "FAIL $*"; failed=1; }
f() { dpkg-deb -f "$1" "$2" 2>/dev/null || true; }
nb=$(ls "$W"/base/*.deb | wc -l); nv=$(ls "$W"/v3/*.deb | wc -l)
[ "$nv" -gt 0 ] && [ "$nv" -le "$nb" ] && ok "the v3 set has $nv packages, the baseline set $nb (companions of packages that hold no code are not rebuilt as variants only if they are not in the v3 set)" || bad "package counts: baseline $nb, v3 $nv"
missing=0; differ=0
for V in "$W"/v3/*.deb; do
	p=$(f "$V" Package); B=$(ls "$W"/base/${p}_*.deb 2>/dev/null | head -1)
	[ -n "$B" ] || { echo "no baseline package for $p"; missing=1; continue; }
	[ "$(f "$V" Architecture-Variant)" = amd64v3 ] || { echo "$p carries no Architecture-Variant"; missing=1; }
	for k in Package Version Architecture Section Priority Multi-Arch Depends Pre-Depends Recommends Suggests Breaks Conflicts Replaces Provides Source; do
		[ "$(f "$B" $k)" = "$(f "$V" $k)" ] || { differ=1; echo "control field $k of $p differs: [$(f "$B" $k)] [$(f "$V" $k)]"; }
	done
	[ "$(dpkg-deb -c "$B" | awk '{print $6}' | sort | md5sum)" = "$(dpkg-deb -c "$V" | awk '{print $6}' | sort | md5sum)" ] || { differ=1; echo "file list of $p differs from the baseline's"; }
done
[ $missing = 0 ] && ok "every v3 package carries Architecture-Variant: amd64v3 from its own build (no repack) and has a baseline twin" || bad 'variant mark or twin missing'
[ $differ = 0 ] && ok "control fields and file lists are equal between each baseline package and its v3 twin" || bad 'control fields or file lists differ'
mkdir -p "$W/xb" "$W/xv"; dpkg-deb -x "$(ls "$W"/base/mesa-libgallium_*.deb)" "$W/xb"; dpkg-deb -x "$(ls "$W"/v3/mesa-libgallium_*.deb)" "$W/xv"
SB=$(find "$W/xb" -name 'libgallium-*.so' | head -1); SV=$(find "$W/xv" -name 'libgallium-*.so' | head -1)
echo "libgallium: $(basename "$SB")"
cmp -s "$SB" "$SV" && bad 'the two libgallium are identical' || ok 'the two libgallium differ'
vex() { objdump -d --no-show-raw-insn "$1" | awk '$2 ~ /^v[a-z]/ || $2 ~ /^(andn|bextr|blsi|blsr|blsmsk|shlx|shrx|sarx|rorx|tzcnt|lzcnt|movbe)$/ || /ymm/' | wc -l; }
cb=$(vex "$SB"); cv=$(vex "$SV")
echo "instructions of the level (VEX, ymm, BMI, LZCNT, MOVBE) in libgallium: baseline $cb, v3 $cv"
[ "$cv" -gt $((cb * 5 + 1000)) ] && ok "the v3 libgallium holds $cv instructions of the level, the baseline $cb (its own run-time dispatched code)" || bad "instruction counts: baseline $cb, v3 $cv"
out=$(cd /sparky-os && PYTHONPATH=/sparky-os python3 -B -m lean.release check-debs --no-record "$W"/base/*.deb "$W"/v3/*.deb 2>&1 | tail -1)
echo "$out" | grep -q "verified $((nb + nv)) packages" && ok "check-debs: the baseline set and the build-time variant set together: $out" || bad "check-debs on both sets: $out"
VD=$W/src; cp "$W"/base/*.deb "$W"/v3/*.deb "$VD/"
T=/work/mesa/t; mkdir -p "$T/sparky-os"; cp -r /sparky-os/repo /sparky-os/lean /sparky-os/iso-build "$T/sparky-os/"; rm -rf "$T/sparky-os/repo/tests"
printf '%s\n' 'import sys' 'sys.exit(0)' >"$T/sparky-os/lean/release.py"
sed -i 's/^ORIGIN="Sparky Stereo OS"/ORIGIN="Toy variants"/' "$T/sparky-os/repo/publish-tree.sh"
export GNUPGHOME=/work/mesa/gnupg; mkdir -m 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' --quick-gen-key 'test' default default never >/dev/null 2>&1
export SPARKY_REPO_KEY=$(gpg --with-colons --list-secret-keys | awk -F: '/^fpr:/ {print $10; exit}') SPARKY_REPO_GNUPGHOME=$GNUPGHOME SPARKY_APPSTREAM=0 SPARKY_INSTALLABLE=off SPARKY_SCRATCH=/work/scratch TMPDIR=/work/scratch
bash "$T/sparky-os/repo/publish-tree.sh" "$VD" /work/mesa/tree >/work/mesa/publish.log 2>&1 && ok 'publish-tree.sh published the baseline, the variant and the i386 set' || { bad 'publish failed'; tail -5 /work/mesa/publish.log; }
grep -E '^Architectures: ' /work/mesa/tree/dists/mashtabba/Release
grep -qE '^Architectures: .*amd64v3' /work/mesa/tree/dists/mashtabba/Release && ok "Release lists amd64v3 beside amd64 and i386" || bad "Release: $(grep ^Arch /work/mesa/tree/dists/mashtabba/Release)"
printf 'base %s\nv3 %s\n' "$(sha256sum $SB | cut -d' ' -f1)" "$(sha256sum $SV | cut -d' ' -f1)" >/work/mesa/hashes
exit $failed
