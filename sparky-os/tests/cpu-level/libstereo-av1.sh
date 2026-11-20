#!/bin/bash
# The first real x86-64-v3 build of one of our libraries, installed by apt by the processor (ORDER 108, milestone 2 part C).
# libstereo-av1 of the published stereo-layer 1.18.0-1+lc1, built twice from that source package with the source's own av-only profile,
# unchanged debian/rules, tests on; the second time with DEB_CFLAGS_MAINT_APPEND and DEB_CXXFLAGS_MAINT_APPEND = -march=x86-64-v3.
# Usage: [POOL=…/pool/main/s/stereo-layer] libstereo-av1.sh BASE_DEB_DIR V3_DEB_DIR WORK   (DOCKER_HOST set; IMAGE defaults to gr108-base:testing-20261027)
#   BASE_DEB_DIR and V3_DEB_DIR hold libstereo-av1_*.deb and libstereo-av-dev_*.deb of each build.
# Checks: the two builds differ in code only (control fields equal, the same shared-library dependencies); the v3 build holds
# instructions of the level and the baseline none; the variant mark is added by a repack; publish-tree.sh (Lean Code gates stubbed in the
# test's copy) publishes both; apt on a faked v3 processor installs the v3 library, on a faked baseline one the baseline library.
set -uo pipefail
BASE=$(cd "${1:?baseline deb folder}" && pwd)
V3=$(cd "${2:?v3 deb folder}" && pwd)
WORK=${3:?work folder}
IMAGE=${IMAGE:-gr108-base:testing-20261027}
HERE=$(cd "$(dirname "$0")" && pwd)
SPARKY_OS=$(cd "$HERE/../.." && pwd)
mkdir -p "$WORK/cpu"
V1=lm,cmov,cx8,fpu,fxsr,mmx,syscall,sse2
V2=$V1,cx16,lahf_lm,popcnt,sse4_1,sse4_2,ssse3
V3F=$V2,avx,avx2,bmi1,bmi2,f16c,fma,abm,movbe,xsave
for l in 1 3; do v=V$l; [ $l = 3 ] && v=V3F; printf 'processor\t: 0\nvendor_id\t: TestCPU\nflags\t\t: %s\n' "${!v//,/ }" >"$WORK/cpu/v$l"; done
HTTPS=(-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro)
rc=0
docker run --rm --cpus 2 --ulimit core=1 --name gr108-av1 -e DEBIAN_FRONTEND=noninteractive "${HTTPS[@]}" -v "$BASE:/base:ro" -v "$V3:/v3:ro" \
	-v "$SPARKY_OS:/sparky-os:ro" -v "${POOL:-/K3D/sparky-repo-r1114a/pool/main/s/stereo-layer}:/tree-pool:ro" -v "$HERE/phase1.sh:/phase1.sh:ro" -v "$WORK:/work" "$IMAGE" bash /phase1.sh || rc=1
for l in 1 3; do
	name=$([ $l = 3 ] && echo 'faked v3 processor' || echo 'faked baseline processor')
	got=$(docker run --rm --cpus 2 --ulimit core=1 --name gr108-av1apt -e DEBIAN_FRONTEND=noninteractive "${HTTPS[@]}" -v "$WORK:/work" -v "$WORK/cpu/v$l:/proc/cpuinfo:ro" \
		-v /K3D/sparky-repo-r1114a:/repo:ro -v "$SPARKY_OS/packages/sparky-stereo-apt:/apt:ro" -v "$HERE/phase2.sh:/phase2.sh:ro" "$IMAGE" bash /phase2.sh 2>&1 | tail -4)
	want=$([ $l = 3 ] && echo v3 || echo base)
	if printf '%s\n' "$got" | grep -qx "installed: $want"; then echo "PASS apt on a $name installs the $want library"; else echo "FAIL apt on a $name: $got"; rc=1; fi
done
exit $rc
