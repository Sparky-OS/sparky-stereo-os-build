#!/bin/bash
# publish-tree.sh and the amd64v3 variant index (ORDER 108), on a throwaway tree in an amd64 debian:testing container; nothing touches a real tree or key.
#   Run: run.sh WORK_FOLDER OLD_SPARKY_OS   (DOCKER_HOST set; IMAGE defaults to gr108-base:testing-20261027)
# The real publish-tree.sh and the real tools it calls run; the three Lean Code gates that need lc1-marked archives (lean.release
# check-selection and check-link) are replaced by no-ops in the test's COPY of lean/release.py, and the AppStream catalogues and the
# installability report are switched off (SPARKY_APPSTREAM=0, SPARKY_INSTALLABLE=off): toy packages cannot pass them.
# Checks: (1) a tree with no variant build is byte-identical, in every index, to what the script of the main branch (the OLD folder) publishes
# (RED_SCRIPT: the script from before the change, passed as the second argument); (2) with a variant build the Release lists amd64v3 and
# binary-amd64v3/Packages is a complete copy; (3) apt on a faked v3 processor takes the v3 build and still installs a baseline-only
# package and an Architecture: all one; (4) the supplanting trap: the same tree with an incomplete variant index hides the baseline-only package.
set -uo pipefail
rc=0
WORK=${1:?work folder}
OLD=${2:?a folder holding the sparky-os subset from before the change (git archive of main: repo, release, lean, config, apt)}
IMAGE=${IMAGE:-gr108-base:testing-20261027}
HERE=$(cd "$(dirname "$0")" && pwd)
SPARKY_OS=$(cd "$HERE/../../.." && pwd)
mkdir -p "$WORK"
docker run --rm --cpus 2 --ulimit core=1 --name gr108-pub -e DEBIAN_FRONTEND=noninteractive \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
	-v "$SPARKY_OS:/sparky-os:ro" -v "$OLD:/old:ro" -v "$HERE/inside.sh:/inside.sh:ro" -v "$WORK:/work" "$IMAGE" bash /inside.sh || rc=1
# Phase 2: apt on the trees, on a faked v3 processor and a faked baseline one
V1=lm,cmov,cx8,fpu,fxsr,mmx,syscall,sse2
V2=$V1,cx16,lahf_lm,popcnt,sse4_1,sse4_2,ssse3
V3=$V2,avx,avx2,bmi1,bmi2,f16c,fma,abm,movbe,xsave
mkdir -p "$WORK/cpu"
for l in 1 3; do v=V$l; printf 'processor\t: 0\nvendor_id\t: TestCPU\nflags\t\t: %s\n' "${!v//,/ }" >"$WORK/cpu/v$l"; done
apt_case() { # name tree cpu expected(a|b|c lines)
	local got
	got=$(docker run --rm --cpus 2 --ulimit core=1 --name gr108-pubapt -e DEBIAN_FRONTEND=noninteractive -v "$WORK:/work" -v "$WORK/cpu/$3:/proc/cpuinfo:ro" \
		-v "$SPARKY_OS/packages/sparky-stereo-apt:/apt:ro" -v "$HERE/inside-apt.sh:/inside-apt.sh:ro" "$IMAGE" sh /inside-apt.sh "$2" 2>&1 | tr '\n' '|')
	if [ "$got" = "$4" ]; then echo "PASS apt, $1: $got"; else echo "FAIL apt, $1: got '$got', wanted '$4'"; rc=1; fi
}
apt_case 'v3 processor, complete variant index' new2 v3 'a built for x86-64-v3|b built for baseline|c, architecture all|'
apt_case 'baseline processor, same tree' new2 v1 'a built for baseline|b built for baseline|c, architecture all|'
apt_case 'v3 processor, tree without a variant' new1 v3 'a built for baseline|b built for baseline|c, architecture all|'
apt_case 'v3 processor, incomplete variant index (the trap)' naive v3 'a built for x86-64-v3|b: not installable|c, architecture all|'
exit $rc
