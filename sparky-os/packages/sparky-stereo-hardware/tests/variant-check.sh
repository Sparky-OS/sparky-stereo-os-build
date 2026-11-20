#!/bin/bash
# The mismatch guard (ORDER 108), end to end in an amd64 debian:testing container: an amd64v3 build installed by apt on a v3 processor, the
# same disk "moved" to an older processor (the /proc/cpuinfo that apt reads and the loader's levels, GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,
# are both faked), the engine told once with its Repair, the Repair installing the baseline build, the notice ended.
# Usage: variant-check.sh PACKAGE_DIR WORK_FOLDER   (DOCKER_HOST set). PACKAGE_DIR is this package's folder: give an older checkout and
# the first check fails (red). The toy repositories are the ones tests/variants of sparky-stereo-apt builds.
set -uo pipefail
PKG=$(cd "${1:?package folder}" && pwd)
WORK=${2:?work folder}
IMAGE=${IMAGE:-gr108-base:testing-20261027}
APTPKG=$(cd "$(dirname "$0")/../../sparky-stereo-apt" && pwd)
HTTPS=(-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro)
mkdir -p "$WORK/toy" "$WORK/cpu"
failed=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; failed=1; }
V1=lm,cmov,cx8,fpu,fxsr,mmx,syscall,sse2
V2=$V1,cx16,lahf_lm,popcnt,sse4_1,sse4_2,ssse3
V3=$V2,avx,avx2,bmi1,bmi2,f16c,fma,abm,movbe,xsave
cpu() { printf 'processor\t: 0\nvendor_id\t: TestCPU\nflags\t\t: %s\n' "${1//,/ }" >"$WORK/cpu/now"; }   # in place: the container's bind mount follows the inode
cpu "$V3"
if [ ! -f "$WORK/toy/complete/dists/toy/Release" ]; then
	docker run --rm --cpus 2 --ulimit core=1 --name gr108-toy "${HTTPS[@]}" -e DEBIAN_FRONTEND=noninteractive \
		-v "$APTPKG/tests/variants:/t:ro" -v "$WORK/toy:/out" "$IMAGE" sh -c \
		'sh /run/https-only-apt.sh && apt-get -y update >/dev/null && apt-get -y install apt-utils >/dev/null && bash /t/make-toy.sh /out && chown -R '"$(id -u):$(id -g)"' /out' >/dev/null || { echo 'FAIL the toy repository'; exit 1; }
fi
C=gr108-vc
docker rm -f $C >/dev/null 2>&1
docker run -d --name $C --cpus 2 --ulimit core=1 "${HTTPS[@]}" -v "$WORK/cpu/now:/proc/cpuinfo:ro" -v "$WORK/toy:/toy:ro" -v "$PKG:/pkg:ro" \
	-v "$APTPKG:/aptpkg:ro" "$IMAGE" sleep 1800 >/dev/null
trap 'docker rm -f $C >/dev/null 2>&1' EXIT
x() { docker exec -e DEBIAN_FRONTEND=noninteractive "$@"; }
x $C sh -c 'sh /run/https-only-apt.sh >/dev/null && apt-get -y update >/dev/null 2>&1 && apt-get -y install python3 >/dev/null 2>&1' || { echo 'FAIL setup'; exit 1; }
x $C sh -c '
	cp /aptpkg/62sparky-stereo-variants /etc/apt/apt.conf.d/ && install -Dm644 /aptpkg/variants/varianttable /usr/share/sparky-stereo-apt/varianttable
	rm -f /etc/apt/sources.list.d/debian.sources; echo "deb [trusted=yes] file:/toy/complete toy main" >/etc/apt/sources.list.d/toy.list
	printf "#!/bin/sh\necho \"\$*\" >>/tmp/engine.log\n" >/usr/local/bin/sparky-stereo-problems; chmod 755 /usr/local/bin/sparky-stereo-problems
	mkdir -p /usr/lib/sparky-stereo-hardware /var/lib/sparky-stereo-problems; : >/tmp/engine.log'
# the file under test is the package's own (red: an older checkout has none)
if [ -f "$PKG/bin/sparky-stereo-variant-check" ]; then
	x $C sh -c 'install -m755 /pkg/bin/sparky-stereo-variant-check /usr/lib/sparky-stereo-hardware/variant-check'; ok 'the guard is in the package'
else
	bad 'the package has no bin/sparky-stereo-variant-check'; exit 1
fi
V=/usr/lib/sparky-stereo-hardware/variant-check
echo '== a v3 processor with the v3 build installed'
x $C sh -c 'apt-get -q update >/dev/null 2>&1 && apt-get -y install sstoy sbonly >/dev/null 2>&1; sstoy' | grep -qx 'sstoy built for x86-64-v3' && ok 'apt installed the amd64v3 build' || bad 'the v3 build was not installed'
x $C grep -q '^Architecture-Variant: amd64v3' /var/lib/dpkg/status && ok 'dpkg keeps Architecture-Variant in its status' || bad 'dpkg status lost the variant field'
x $C $V check; x $C cat /tmp/engine.log | grep -q . && bad 'a v3 processor with a v3 build was told' || ok 'nothing is told on a processor that has the level'
echo '== the disk moves to an older processor'
cpu "$V2"
T='GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2'
x -e $T $C $V list | tee "$WORK/list.out"
grep -q '^cpu-level v2' "$WORK/list.out" && grep -q '^mismatch sstoy amd64v3' "$WORK/list.out" && ok 'the v3 build is found on a v2 processor' || bad 'no mismatch found'
grep -q 'sbonly' "$WORK/list.out" && bad 'a baseline package was listed' || ok 'a baseline package is not listed'
x -e $T $C $V check
x $C cat /tmp/engine.log | tee "$WORK/engine1.out"
grep -qx 'keep --repair \["sparky-stereo-hardware","--variants"\] sparky-stereo-hardware variant-mismatch LOCAL85 sstoy v2' "$WORK/engine1.out" && ok 'the engine keeps the notice once, with its Repair, the package and the processor level' || bad 'the notice'
echo '== the Repair'
: >"$WORK/e"; x $C sh -c ': >/tmp/engine.log; touch /var/lib/sparky-stereo-problems/sparky-stereo-hardware_variant-mismatch.json'
x -e $T $C $V repair >"$WORK/repair.out" 2>&1; echo "repair exit $?"
x $C sstoy | grep -qx 'sstoy built for baseline' && ok 'apt reinstalled the baseline build' || bad 'sstoy is not the baseline build'
x $C grep -q '^Architecture-Variant:' /var/lib/dpkg/status && bad 'the variant field is still in the status' || ok 'no package carries a variant any more'
x -e $T $C $V list | grep -q mismatch && bad 'a mismatch is left' || ok 'the check finds nothing left'
x $C cat /tmp/engine.log | grep -qx 'clear sparky-stereo-hardware variant-mismatch' && ok 'the notice ended' || bad 'the notice was not cleared'
echo '== the same disk back on the v3 processor: the baseline build stays, nothing is told'
cpu "$V3"; x $C sh -c ': >/tmp/engine.log; rm -f /var/lib/sparky-stereo-problems/*'; x $C $V check; x $C cat /tmp/engine.log | grep -q . && bad 'told on a processor that has the level' || ok 'nothing is told'
exit $failed
