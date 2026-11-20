#!/bin/bash
# The edition's Mesa at x86-64-v3 installed by apt by the processor (ORDER 108, milestone 5 part B).
# Usage: [KEY_PKG=… KEY_GLOB=… KEY_LIB=… INSTALL=… TAG=… NO_I386=1 MIN_EXTRA=…] mesa-apt.sh BASE_DIR V3_DIR I386_DIR|- WORK
#   (the defaults are Mesa's; stereo-layer: KEY_PKG=libstereo-dibr1 KEY_GLOB='libstereo-dibr.so.*.*' KEY_LIB='libstereo-dibr.so.*.*' INSTALL=libstereo-dibr1 TAG=sl NO_I386=1)   (DOCKER_HOST set; IMAGE defaults to gr108-base:testing-20261027; STAGE_HW is the folder with
#   sparky-stereo-hardware_*.deb for the guard; POOL is the published tree, /K3D/sparky-repo-r1114a by default)
#   BASE_DIR holds the baseline amd64 mesa .deb set of the version (mesa-libgallium, libgl1-mesa-dri, ... and the -lc-hr companions), V3_DIR the
#   amd64v3 set built by mesa-v3.sh, I386_DIR the baseline i386 set of the same version.
# Phase 1 (one container): the two builds differ in code only; the v3 library holds instructions of the level; check-debs takes both sets together; publish-tree.sh
#   publishes the baseline and the variant into a throwaway tree.
# Phase 2 (three containers whose /proc/cpuinfo is a faked processor): a v3 processor takes the v3 build, a baseline processor the baseline, the opt-out
#   (APT::Architecture-Variants "") wins on a v3 processor, the baseline i386 build installs beside the v3 amd64 one, and the hardware guard says so in the
#   person's words when the v3 build sits on a processor without v3.
set -uo pipefail
BASE=$(cd "${1:?baseline amd64 deb folder}" && pwd)
V3=$(cd "${2:?v3 deb folder}" && pwd)
I386=${3:?baseline i386 deb folder, or - for none}; WORK=${4:?work folder}; mkdir -p "$WORK/empty"; if [ "$I386" = - ]; then I386=$(cd "$WORK/empty" && pwd); else I386=$(cd "$I386" && pwd); fi
WORK=${4:?work folder}
IMAGE=${IMAGE:-gr108-base:testing-20261027}
POOL=${POOL:-/K3D/sparky-repo-r1114a}
HERE=$(cd "$(dirname "$0")" && pwd)
SPARKY_OS=$(cd "$HERE/../.." && pwd)
mkdir -p "$WORK/cpu"
V1=lm,cmov,cx8,fpu,fxsr,mmx,syscall,sse2
V2=$V1,cx16,lahf_lm,popcnt,sse4_1,sse4_2,ssse3
V3F=$V2,avx,avx2,bmi1,bmi2,f16c,fma,abm,movbe,xsave
for l in 1 3; do v=V$l; [ $l = 3 ] && v=V3F; printf 'processor\t: 0\nvendor_id\t: TestCPU\nflags\t\t: %s\n' "${!v//,/ }" >"$WORK/cpu/v$l"; done
HTTPS=(-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro)
rc=0
docker run --rm --cpus 2 --ulimit core=1 --name gr108-mesa-p1 -e DEBIAN_FRONTEND=noninteractive -e KEY_PKG -e KEY_GLOB -e TAG -e MIN_EXTRA "${HTTPS[@]}" -v "$BASE:/base:ro" -v "$V3:/v3:ro" -v "$I386:/i386:ro" \
	-v "$SPARKY_OS:/sparky-os:ro" -v "$HERE/mesa-phase1.sh:/phase1.sh:ro" -v "$WORK:/work" "$IMAGE" bash /phase1.sh || rc=1
for case in v3 base optout v3-on-base; do
	case $case in
		v3) cpu=v3; mode=install; want=v3; name='faked v3 processor';;
		base) cpu=v1; mode=install; want=base; name='faked baseline processor';;
		optout) cpu=v3; mode=install-optout; want=base; name='faked v3 processor with the opt-out';;
		v3-on-base) cpu=v1; mode=guard; want=guard; name='processor without v3 (the loader offers v2) with the v3 build installed';;
	esac
	got=$(docker run --rm --cpus 2 --ulimit core=1 --name gr108-mesa-p2 -e DEBIAN_FRONTEND=noninteractive -e MODE=$mode -e KEY_PKG -e KEY_LIB -e INSTALL -e TAG -e NO_I386 "${HTTPS[@]}" -v "$WORK:/work" -v "$WORK/cpu/$cpu:/proc/cpuinfo:ro" \
		-v "$POOL:/repo:ro" -v "$I386:/i386:ro" -v "${STAGE_HW:?folder with sparky-stereo-hardware}:/hw:ro" -v "$SPARKY_OS/packages/sparky-stereo-apt:/apt:ro" \
		-v "$HERE/mesa-phase2.sh:/phase2.sh:ro" "$IMAGE" bash /phase2.sh 2>&1 | tail -8)
	if printf '%s\n' "$got" | grep -qx "result: $want"; then echo "PASS apt on a $name: $want"; printf '%s\n' "$got" | grep -v '^result' | sed 's/^/     /'; else echo "FAIL apt on a $name: $got"; rc=1; fi
done
exit $rc
