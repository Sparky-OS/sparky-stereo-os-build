#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Proves that the edition's linux-libc-dev and Debian's cross toolchains install together (ORDER 256), in fresh Debian testing
# amd64 containers with the edition's signed repository and pins and their own APT state:
#   control A, the edition's repository as published: Debian's linux-libc-dev-armhf-cross Depends linux-libc-dev (= Debian's
#     version), so asking for the edition's linux-libc-dev and crossbuild-essential-armhf together fails, and on a system that
#     has Debian's cross toolchain the edition's linux-libc-dev comes only with the toolchain removed; an armhf program that
#     uses struct drm_hdmi_3d_metadata does not compile against Debian's headers;
#   case B, the same plus the candidate linux-libc-dev-ARCH-cross packages: the edition's linux-libc-dev, every Debian
#     cross toolchain the workstation carries (armhf with gcc 14, 15 and 16, x32, i386, amd64) and all 30 cross packages
#     install in one transaction with nothing removed, downgraded or held, the other crossbuild-essential sets resolve, and the
#     armhf (and i386, x32) program compiles, links and (armhf, i386) runs under qemu-user with the edition's structure;
#   case C, the workstation's way: Debian's armhf toolchain installed first (the edition's pins already block Debian's builds of
#     what the edition ships, qemu-user among them, so qemu-user comes later from the edition), then the edition's repository
#     and the candidates:
#     an ordinary upgrade replaces linux-libc-dev and linux-libc-dev-armhf-cross, removes nothing, and the program compiles.
#
#   kernel/tests/libc-dev-cross-proof.sh CANDIDATE-DIR POOL IMAGE
# CANDIDATE-DIR holds the linux-libc-dev-*-cross .debs; POOL is a copy of the published pool (its sparky-stereo-apt,
# sparky-stereo-keyring and deb-multimedia-keyring give the sources, key and pins, as an edition system has them); IMAGE is a
# Debian testing amd64 image pinned by digest. REPO_HOST, when set (a LAN address of repo.sparkyos.org), is passed as
# --add-host. START, when set, is a directory of Debian .debs installed first in case C (Debian's linux-libc-dev and
# linux-libc-dev-armhf-cross at the workstation's version, 7.2.11-1, from snapshot.debian.org). Prints the log; exit status 1 on any failure.
set -eu
CAND=$(readlink -f "${1:?usage: libc-dev-cross-proof.sh candidate-dir pool image}")
POOL=$(readlink -f "${2:?pool}")
IMAGE=${3:?image}
HOST=; [ -n "${REPO_HOST:-}" ] && HOST="--add-host repo.sparkyos.org:$REPO_HOST"
run() {
	name=$1; shift
	# shellcheck disable=SC2086
	docker run --rm --name "libc-dev-cross-proof-$name" --platform linux/amd64 --cpus 4 --memory 3g $HOST \
		-v "$CAND":/proof/candidate:ro -v "$POOL":/proof/pool:ro ${START:+-v "$START":/proof/start:ro} -e CASE="$name" "$IMAGE" sh -eu -c "$INNER"
}
INNER='
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
fail() { echo "FAIL: $*"; exit 1; }
edition() {
	# the published sparky-stereo-apt payload (sources and pins) and keyrings, as an edition system has them
	for p in sparky-stereo-keyring deb-multimedia-keyring sparky-stereo-apt; do
		deb=$(ls /proof/pool/main/*/$p/${p}_*_all.deb | sort -V | tail -1)
		dpkg-deb -x "$deb" /
		echo "edition APT setup from $(basename "$deb") sha256 $(sha256sum "$deb" | cut -c1-16)"
	done
	ls /etc/apt/sources.list.d /etc/apt/preferences.d | tr "\n" " "; echo
}
candidates() {
	mkdir -p /srv/candidate
	cp /proof/candidate/*.deb /srv/candidate/
	(cd /srv/candidate && apt-ftparchive packages . > Packages &&
	 apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo OS" -o APT::FTPArchive::Release::Label="Sparky Stereo OS candidate" \
		-o APT::FTPArchive::Release::Suite=mashtabba -o APT::FTPArchive::Release::Codename=mashtabba release . > Release)
	printf "Types: deb\nURIs: file:/srv/candidate\nSuites: ./\nTrusted: yes\n" > /etc/apt/sources.list.d/candidate.sources
	echo "candidates (unsigned, Origin Sparky Stereo OS as published): $(ls /srv/candidate/*.deb | wc -l) packages"
}
summary() {
	sed -n "/^The following packages will be upgraded:/,/^[0-9]/p" "$1" | sed "\$d" | tr -s " \n" " "; echo
	grep -E "^[0-9]+ upgraded|DOWNGRADED|REMOVED|^Remv|^E:|held" "$1" || true
}
clean_transaction() {
	grep -q "^E:" "$1" && fail "apt error, see above"
	grep -Eq "DOWNGRADED|^Remv|The following packages will be REMOVED" "$1" && fail "a removal or downgrade"
	grep -Eq "^[0-9]+ upgraded, [0-9]+ newly installed, 0 to remove and [0-9]+ not upgraded" "$1" || fail "removals"
	test -z "$(apt-mark showhold)" || fail "held packages: $(apt-mark showhold)"
}
cat > /proof/t.c <<"EOC"
#include <stddef.h>
#include <stdio.h>
#include <asm/unistd.h>
#include <drm/drm_mode.h>
int main(void)
{
	struct drm_hdmi_3d_metadata m = { .type = 0x81, .length = 5 };
	printf("sizeof=%zu type@%zu length@%zu data@%zu NR_write=%d\n", sizeof m,
	       offsetof(struct drm_hdmi_3d_metadata, type), offsetof(struct drm_hdmi_3d_metadata, length),
	       offsetof(struct drm_hdmi_3d_metadata, data), __NR_write);
	return m.type != 0x81 || m.length != 5;
}
EOC
apt-get -qq update >/dev/null 2>&1
apt-get -y -qq install ca-certificates apt-utils file binutils >/dev/null 2>&1
TOOLS="crossbuild-essential-armhf libc6-dev-armhf-cross gcc-14-arm-linux-gnueabihf g++-14-arm-linux-gnueabihf gcc-15-arm-linux-gnueabihf g++-15-arm-linux-gnueabihf gcc-16-arm-linux-gnueabihf g++-16-arm-linux-gnueabihf crossbuild-essential-amd64 gcc-x86-64-linux-gnux32 libc6-dev-x32-cross crossbuild-essential-i386 libc6-dev-i386-cross libc6-amd64-cross libc6-i386-amd64-cross libc6-x32-amd64-cross libc6-x32-i386-cross libc6-i386-cross qemu-user"
case $CASE in
control)
	echo "== A. control: the edition repository as published, no candidate"
	edition; apt-get -qq update
	apt-cache policy linux-libc-dev linux-libc-dev-armhf-cross | grep -E "^[a-z]|Candidate|[0-9] (500|1001)"
	echo "-- A1. the edition linux-libc-dev with the armhf cross toolchain, in one request"
	if apt-get -y install --no-install-recommends linux-libc-dev crossbuild-essential-armhf libc6-dev-armhf-cross > /proof/a1.log 2>&1; then
		fail "installed together without the candidate packages"; fi
	grep -E "Depends|E:|unmet|but" /proof/a1.log | head -8
	echo "-- A2. the workstation state: Debian toolchain installed first (edition repository off), then the edition repository"
	mkdir -p /proof/off; mv /etc/apt/sources.list.d/sparky-stereo*.sources /proof/off/; apt-get -qq update
	apt-get -y -qq install --no-install-recommends crossbuild-essential-armhf libc6-dev-armhf-cross > /proof/a2.log 2>&1 || { tail /proof/a2.log; fail "Debian toolchain"; }
	dpkg-query -W -f "\${Package} \${Version}\n" linux-libc-dev linux-libc-dev-armhf-cross libc6-dev-armhf-cross crossbuild-essential-armhf
	echo "-- A3. armhf program against Debian headers"
	if arm-linux-gnueabihf-gcc /proof/t.c -o /proof/t 2>/proof/a3.err; then fail "compiled against Debian headers"; fi
	grep -m2 error /proof/a3.err
	if arm-linux-gnueabihf-gcc -nostdinc -isystem "$(arm-linux-gnueabihf-gcc -print-file-name=include)" -isystem /usr/arm-linux-gnueabihf/include -c /proof/t.c -o /proof/s.o 2>/proof/a3s.err; then
		fail "compiled against the sysroot layout of Debian"; fi
	echo "sysroot layout only (the linux-libc-dev-armhf-cross of Debian): $(grep -m1 error /proof/a3s.err)"
	mv /proof/off/*.sources /etc/apt/sources.list.d/; apt-get -qq update
	apt-get -s full-upgrade > /proof/a4.log 2>&1 || true
	echo "-- A4. apt-get -s full-upgrade with the edition repository: what happens to linux-libc-dev and the toolchain"
	grep -E "^(Inst|Remv) (linux-libc-dev|libc6-dev-armhf|crossbuild|gcc-|g\+\+-|libstdc)" /proof/a4.log || echo "(no line for linux-libc-dev: it stays at Debian'"'"'s version)"
	grep -E "^[0-9]+ upgraded" /proof/a4.log
	if grep -Eq "^Inst linux-libc-dev " /proof/a4.log && ! grep -q "^Remv" /proof/a4.log; then
		fail "the upgrade takes the edition linux-libc-dev and keeps the toolchain without the candidates"; fi
	echo "-- A5. apt-get -s install linux-libc-dev: what the edition headers cost without the candidates"
	apt-get -s install linux-libc-dev > /proof/a5.log 2>&1 || true
	grep -E "^Remv|^Inst linux-libc-dev|^[0-9]+ upgraded" /proof/a5.log
	grep -q "^Remv libc6-dev-armhf-cross" /proof/a5.log || fail "expected the cross toolchain removal"
	echo "CONTROL REPRODUCED: the edition linux-libc-dev and the armhf cross toolchain exclude each other";;
fresh)
	echo "== B. fresh: the edition repository plus the candidate cross packages"
	edition; candidates; apt-get -qq update
	apt-cache policy linux-libc-dev linux-libc-dev-armhf-cross | grep -E "^[a-z]|Candidate|[0-9] (500|1001)"
	CROSS=$(cd /srv/candidate && ls *.deb | sed "s/_.*//" | tr "\n" " ")
	echo "-- B1. one transaction: linux-libc-dev, the workstation cross toolchains, all 30 cross packages"
	apt-get -y install --no-install-recommends linux-libc-dev $TOOLS $CROSS > /proof/b1.log 2>&1 || { tail -20 /proof/b1.log; fail "install"; }
	summary /proof/b1.log; clean_transaction /proof/b1.log
	dpkg-query -W -f "\${Package} \${Version}\n" linux-libc-dev linux-libc-dev-armhf-cross linux-libc-dev-i386-cross linux-libc-dev-x32-cross libc6-dev-armhf-cross crossbuild-essential-armhf gcc-14-arm-linux-gnueabihf gcc-15-arm-linux-gnueabihf gcc-16-arm-linux-gnueabihf gcc-x86-64-linux-gnux32 gcc-i686-linux-gnu
	test "$(dpkg-query -W -f "\${Version}" linux-libc-dev)" = 7.3.0-13+lc1 || fail "not the edition linux-libc-dev"
	test "$(dpkg -l "linux-libc-dev*-cross" | grep -c "^ii")" = 30 || fail "not all 30 cross packages"
	dpkg --audit; echo "dpkg --audit: empty above means clean"
	echo "-- B2. every other crossbuild-essential set resolves beside them (simulated)"
	others=$(apt-cache pkgnames crossbuild-essential- | sort | tr "\n" " ")
	apt-get -s install --no-install-recommends $others > /proof/b2.log 2>&1 || { tail /proof/b2.log; fail "crossbuild-essential sets"; }
	summary /proof/b2.log; clean_transaction /proof/b2.log; echo "simulated: $others"
	echo "-- B3. broken links: none"
	n=0; for p in $CROSS; do for f in $(dpkg -L $p | grep "/include/"); do [ -L "$f" ] && { [ -e "$f" ] || { echo "dangling $f"; n=$((n+1)); }; }; done; done
	test "$n" = 0 || fail "$n dangling links"; echo "all links of the 30 packages resolve"
	echo "-- B4. compile, link and run"
	for cc in arm-linux-gnueabihf-gcc-14 arm-linux-gnueabihf-gcc-15 arm-linux-gnueabihf-gcc-16 i686-linux-gnu-gcc x86_64-linux-gnux32-gcc; do
		# -fno-canonical-system-headers: -H prints the path the search found, not its resolved target
		$cc /proof/t.c -o /proof/t-$cc -H -fno-canonical-system-headers 2>/proof/h-$cc.txt || fail "$cc"
		used=$(grep -m1 "drm_mode.h" /proof/h-$cc.txt | sed "s/^\.* //")
		echo "$cc: $(file -b /proof/t-$cc | cut -d, -f1-2); drm_mode.h found at $used -> $(readlink -f "$used") ($(dpkg -S "$(readlink -f "$used")" | cut -d: -f1))"
		# the sysroot layout alone (Debian TC, #1065416, point 3): the headers of the compiler and /usr/GNU-TYPE/include only
		gnu=${cc%-gcc*}
		$cc -nostdinc -isystem "$($cc -print-file-name=include)" -isystem /usr/$gnu/include -c /proof/t.c -o /proof/s-$cc.o -H -fno-canonical-system-headers 2>/proof/s-$cc.txt || { cat /proof/s-$cc.txt | grep -v "^\." | head -5; fail "$cc with the sysroot layout only"; }
		echo "   sysroot layout only: compiles, drm_mode.h at $(grep -m1 "drm_mode.h" /proof/s-$cc.txt | sed "s/^\.* //"), asm/unistd.h at $(grep -m1 "asm/unistd.h" /proof/s-$cc.txt | sed "s/^\.* //")"
	done
	for cc in arm-linux-gnueabihf-gcc-14 arm-linux-gnueabihf-gcc-15 arm-linux-gnueabihf-gcc-16; do
		out=$(qemu-arm -L /usr/arm-linux-gnueabihf /proof/t-$cc); echo "qemu-arm $cc: $out"
		test "$out" = "sizeof=32 type@0 length@1 data@2 NR_write=4" || fail "armhf layout"
	done
	out=$(qemu-i386 -L /usr/i686-linux-gnu /proof/t-i686-linux-gnu-gcc); echo "qemu-i386: $out"
	test "$out" = "sizeof=32 type@0 length@1 data@2 NR_write=4" || fail "i386 layout"
	test "$(readelf -h /proof/t-x86_64-linux-gnux32-gcc | sed -n "s/ *Class: *//p")" = ELF32 || fail "x32 class"
	echo "PASS: fresh";;
upgrade)
	echo "== C. the workstation way: Debian armhf toolchain first, then the edition repository and the candidates"
	start=; [ -d /proof/start ] && start=$(ls /proof/start/*.deb)
	apt-get -y -qq install --no-install-recommends $start crossbuild-essential-armhf libc6-dev-armhf-cross > /proof/c0.log 2>&1 || { tail /proof/c0.log; fail "Debian toolchain"; }
	dpkg-query -W -f "before: \${Package} \${Version}\n" linux-libc-dev linux-libc-dev-armhf-cross
	ls -ld /usr/share/doc/linux-libc-dev-armhf-cross
	edition; candidates; apt-get -qq update
	echo "-- C1. apt-get full-upgrade"
	apt-get -y full-upgrade --no-install-recommends > /proof/c1.log 2>&1 || { tail -20 /proof/c1.log; fail "upgrade"; }
	summary /proof/c1.log; clean_transaction /proof/c1.log
	grep -E "^(Unpacking|Setting up) linux-libc-dev" /proof/c1.log
	dpkg-query -W -f "after: \${Package} \${Version}\n" linux-libc-dev linux-libc-dev-armhf-cross libc6-dev-armhf-cross crossbuild-essential-armhf
	test "$(dpkg-query -W -f "\${Version}" linux-libc-dev)" = 7.3.0-13+lc1 || fail "linux-libc-dev not upgraded"
	test "$(dpkg-query -W -f "\${Version}" linux-libc-dev-armhf-cross)" = "$(dpkg-deb -f /srv/candidate/linux-libc-dev-armhf-cross_*_all.deb Version)" || fail "cross not upgraded"
	ls -ld /usr/share/doc/linux-libc-dev-armhf-cross; test -d /usr/share/doc/linux-libc-dev-armhf-cross -a ! -L /usr/share/doc/linux-libc-dev-armhf-cross || fail "doc is not a directory"
	test -f /usr/share/doc/linux-libc-dev-armhf-cross/copyright || fail "no copyright of its own"
	test -f /usr/share/doc/linux-libc-dev/copyright -a -f /usr/share/doc/linux-libc-dev/changelog.Debian.gz || fail "linux-libc-dev documentation lost"
	dpkg --audit; echo "dpkg --audit: empty above means clean"
	apt-get -y -qq install --no-install-recommends qemu-user > /proof/c1q.log 2>&1 || { tail /proof/c1q.log; fail "qemu-user"; }
	arm-linux-gnueabihf-gcc /proof/t.c -o /proof/t; out=$(qemu-arm -L /usr/arm-linux-gnueabihf /proof/t); echo "qemu-arm: $out"
	test "$out" = "sizeof=32 type@0 length@1 data@2 NR_write=4" || fail "armhf layout"
	echo "-- C2. and back: removing the cross package keeps linux-libc-dev"
	apt-get -y -qq remove linux-libc-dev-armhf-cross libc6-dev-armhf-cross crossbuild-essential-armhf > /proof/c2.log 2>&1
	dpkg-query -W -f "\${Package} \${Version} \${db:Status-Abbrev}\n" linux-libc-dev; test ! -e /usr/share/doc/linux-libc-dev-armhf-cross || fail "doc left behind"
	echo "PASS: upgrade";;
esac
'
case=${CASE:-all}
for c in control fresh upgrade; do
	[ "$case" = all ] || [ "$case" = "$c" ] || continue
	run "$c"
done
