#!/bin/bash
# The variants test (ORDER 108). red: the published sparky-stereo-apt on an x86-64-v3 processor takes the baseline build (must FAIL the v3
# expectation). green: the same plus this package's two files takes the amd64v3 build on v3, the baseline on v2 and on a baseline processor,
# the baseline when the person opts out, and Debian's own repository is untouched. Control: an amd64v3 index that is not a full copy hides a
# baseline-only package (why the repository must publish a complete copy).
# Usage: run.sh PUBLISHED_DEB WORK_FOLDER   (DOCKER_HOST set; IMAGE defaults to gr108-base:testing-20261027, an amd64 debian:testing by digest)
# Containers: --cpus 2, --ulimit core=0, --network none except the toy-repository builder and the Debian-repository case, which use the
# https-only apt helper (/K3D/partners/https-only-apt.sh) as the house rules ask.
set -euo pipefail
PUB=${1:?published sparky-stereo-apt .deb}
WORK=${2:?work folder}
IMAGE=${IMAGE:-gr108-base:testing-20261027}
HERE=$(cd "$(dirname "$0")" && pwd)
PKGDIR=$(cd "$HERE/../.." && pwd)
HTTPS=(-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro)
COMMON=(--rm --cpus 2 --ulimit core=0 --user "$(id -u):$(id -g)")
mkdir -p "$WORK"/{red,green,cpu,toy,opt}
rm -rf "$WORK/red" "$WORK/green"; mkdir -p "$WORK/red" "$WORK/green"

# the published package's files, and this package's
(cd "$WORK/red" && ar p "$PUB" data.tar.xz | tar -xJ ./etc/apt/apt.conf.d ./usr/share 2>/dev/null || true)
cp -a "$WORK/red/." "$WORK/green/"
install -Dm644 "$PKGDIR/62sparky-stereo-variants" "$WORK/green/etc/apt/apt.conf.d/62sparky-stereo-variants"
install -Dm644 "$PKGDIR/variants/varianttable" "$WORK/green/usr/share/sparky-stereo-apt/varianttable"
printf '%s\n' '// the person turns it off' 'APT::Architecture-Variants "";' >"$WORK/opt/99local"

# processors: flag lists are the psABI levels as apt's table writes them
V1=lm,cmov,cx8,fpu,fxsr,mmx,syscall,sse2
V2=$V1,cx16,lahf_lm,popcnt,sse4_1,sse4_2,ssse3
V3=$V2,avx,avx2,bmi1,bmi2,f16c,fma,abm,movbe,xsave
for l in 1 2 3; do v=V$l; printf 'processor\t: 0\nvendor_id\t: TestCPU\nflags\t\t: %s\n' "${!v//,/ }" >"$WORK/cpu/v$l"; done

# toy repositories
if [ ! -f "$WORK/toy/complete/dists/toy/Release" ]; then
	docker run --rm --cpus 2 --ulimit core=0 --name gr108-toy "${HTTPS[@]}" -e DEBIAN_FRONTEND=noninteractive \
		-v "$HERE:/t:ro" -v "$WORK/toy:/out" "$IMAGE" sh -c \
		'sh /run/https-only-apt.sh && apt-get -y update >/dev/null && apt-get -y install apt-utils >/dev/null && bash /t/make-toy.sh /out && chown -R '"$(id -u):$(id -g)"' /out'
fi

fail=0
# case NAME ROOT CPU REPO OPTOUT EXPECTED_SSTOY EXPECTED_SBONLY
one() {
	local name=$1 root=$2 cpu=$3 repo=$4 opt=$5 want1=$6 want2=$7 out got1 got2
	local mounts=(-v "$WORK/$root:/overlay:ro" -v "$WORK/toy:/toy:ro" -v "$HERE/inside.sh:/inside.sh:ro")
	[ "$cpu" = real ] || mounts+=(-v "$WORK/cpu/$cpu:/proc/cpuinfo:ro")
	[ "$opt" = no ] || mounts+=(-v "$WORK/opt/99local:/overlay-extra/99local:ro")
	out=$(docker run "${COMMON[@]}" --user 0:0 --network none --name gr108-case "${mounts[@]}" "$IMAGE" sh -c \
		'cp -a /overlay/. / && { [ ! -f /overlay-extra/99local ] || cp /overlay-extra/99local /etc/apt/apt.conf.d/99local; }
		 sh /inside.sh /toy/'"$repo"' && apt-get -y install sstoy >/dev/null 2>&1 && sstoy;
		 apt-get -y install sbonly >/dev/null 2>&1 && sbonly || echo "sbonly: not installable"' 2>&1) || true
	got1=$(printf '%s\n' "$out" | sed -n 1p); got2=$(printf '%s\n' "$out" | sed -n 2p)
	if [ "$got1" = "$want1" ] && [ "$got2" = "$want2" ]; then
		printf 'PASS %-34s %s | %s\n' "$name" "$got1" "$got2"
	else
		printf 'FAIL %-34s got "%s" | "%s", wanted "%s" | "%s"\n' "$name" "$got1" "$got2" "$want1" "$want2"
		return 1
	fi
}
B1='sstoy built for baseline'; V3T='sstoy built for x86-64-v3'; SB='sbonly built for baseline'
echo '== red: the published package on a v3 processor must give the v3 build (expected to FAIL)'
red=0; one 'red published, v3 cpu' red v3 complete no "$V3T" "$SB" || red=1
[ $red = 1 ] || { echo 'the red case passed: the test cannot fail'; fail=1; }
echo '== green'
one 'green v3 cpu' green v3 complete no "$V3T" "$SB" || fail=1
one 'green v2 cpu' green v2 complete no "$B1" "$SB" || fail=1
one 'green baseline cpu' green v1 complete no "$B1" "$SB" || fail=1
one 'green v3 cpu, person opts out' green v3 complete yes "$B1" "$SB" || fail=1
echo '== control: an amd64v3 index that is not a full copy hides sbonly'
one 'green v3 cpu, incomplete index' green v3 incomplete no "$V3T" 'sbonly: not installable' || fail=1
echo '== Debian own repository untouched (network)'
dres=$(docker run "${COMMON[@]}" --user 0:0 --name gr108-case "${HTTPS[@]}" -e DEBIAN_FRONTEND=noninteractive -v "$WORK/green:/overlay:ro" \
	-v "$WORK/cpu/v3:/proc/cpuinfo:ro" "$IMAGE" sh -c 'cp -a /overlay/. / && sh /run/https-only-apt.sh >/dev/null && apt-get update 2>&1 | grep -c -i "amd64v3" ; apt-cache policy coreutils | sed -n "2p"' 2>&1) || true
echo "$dres" | tr '\n' ' '; echo
[ "$(echo "$dres" | sed -n 1p)" = 0 ] && echo 'PASS debian: no amd64v3 index asked for' || { echo 'FAIL debian'; fail=1; }
echo "$dres" | sed -n 2p | grep -q Installed && echo 'PASS debian: coreutils resolves' || { echo 'FAIL debian policy'; fail=1; }
exit $fail
