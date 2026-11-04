#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# ORDER 346f-1: what cannot work where it should is kept by the edition's engine, and what is by design is not.
# Runs the boot decision (the script given, installed from a package or from the tree) against made-up sysfs trees in a
# container as root, with the engine installed, and compares the problems the engine keeps with the expected ones.
# Usage: problems-proof.sh SCRIPT        exit 0 only when every case matches (the published 0.1.1 fails it: red)
set -u
SCRIPT=${1:?the boot decision script}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
PKG=sparky-stereo-vram-boost
fails=0
gpu() { # gpu CASE ADDRESS DRIVER
	mkdir -p "$T/$1/pci/$2" "$T/$1/drivers/$3"
	ln -s "$T/$1/drivers/$3" "$T/$1/pci/$2/driver"
}
setup() { # setup CASE CONTROLLERS [REGION...]
	local c=$1 ctl=$2; shift 2
	mkdir -p "$T/$c/cg" "$T/$c/pci"
	echo "$ctl" >"$T/$c/cg/cgroup.controllers"
	: >"$T/$c/cg/dmem.capacity"
	for r in "$@"; do echo "$r" >>"$T/$c/cg/dmem.capacity"; done
}
run() { # run CASE MODE -> exit status in $status
	printf 'SPARKY_STEREO_VRAM_BOOST=%s\n' "$2" >"$T/$1/defaults"
	SPARKY_STEREO_VRAM_BOOST_RUN=$T/$1/run SPARKY_STEREO_VRAM_BOOST_CGROUP=$T/$1/cg SPARKY_STEREO_VRAM_BOOST_PCI=$T/$1/pci \
		SPARKY_STEREO_VRAM_BOOST_DEFAULTS=$T/$1/defaults SPARKY_STEREO_VRAM_BOOST_WAIT=${WAIT:-1} \
		"$SCRIPT" >"$T/$1/out" 2>&1
	status=$?
}
kept() { # the keys the engine keeps for the package, sorted, space separated
	sparky-stereo-problems list --json "$PKG" 2>/dev/null | python3 -c 'import json,sys; print(" ".join(sorted(r["key"] for r in json.load(sys.stdin))))'
}
check() { # check CASE MODE "EXPECTED KEYS" EXPECTED-DECISION EXPECTED-STATUS
	local c=$1 mode=$2 want=$3 decision=$4 wstatus=$5
	run "$c" "$mode"
	local got dec
	got=$(kept)
	dec=$(sed -n 's/^decision=//p' "$T/$c/run/state" 2>/dev/null)
	if [ "$got" = "$want" ] && [ "$dec" = "$decision" ] && [ "$status" = "$wstatus" ]; then
		echo "PASS $c mode=$mode problems=[$got] decision=$dec exit=$status"
	else
		echo "FAIL $c mode=$mode problems=[$got] (want [$want]) decision=$dec (want $decision) exit=$status (want $wstatus)"
		fails=$((fails + 1))
	fi
}
CTL="cpuset cpu io memory hugetlb pids rdma misc dmem"
NOCTL="cpuset cpu io memory hugetlb pids rdma misc"
rm -rf /var/lib/sparky-stereo-problems/"$PKG"_*.json
# by design, nothing is kept
setup d-no "$CTL" "drm/0000:03:00.0/vram 8573157376"; gpu d-no 0000:03:00.0 amdgpu
check d-no no "" off 0
setup d-nvidia "$CTL"; gpu d-nvidia 0000:01:00.0 nvidia
check d-nvidia auto "" off 0
setup d-nvidia-nodmem "$NOCTL"; gpu d-nvidia-nodmem 0000:01:00.0 nvidia
check d-nvidia-nodmem auto "" off 0
setup d-nogpu "$NOCTL"
check d-nogpu auto "" off 0
setup d-healthy "$CTL" "drm/0000:03:00.0/vram 8573157376"; gpu d-healthy 0000:03:00.0 amdgpu
check d-healthy auto "" on 0
setup d-xe "$CTL" "drm/0000:00:02.0/vram0 4294967296"; gpu d-xe 0000:00:02.0 xe
check d-xe auto "" on 0
setup d-i915 "$NOCTL"; gpu d-i915 0000:00:02.0 i915
check d-i915 auto "" off 0
# failures, kept
setup f-mode "$CTL" "drm/0000:03:00.0/vram 8573157376"; gpu f-mode 0000:03:00.0 amdgpu
check f-mode sometimes "mode" off 0
setup f-kernel "$NOCTL"; gpu f-kernel 0000:03:00.0 amdgpu
check f-kernel auto "kernel" off 0
setup f-kernel-nouveau "$NOCTL"; gpu f-kernel-nouveau 0000:01:00.0 nouveau
check f-kernel-nouveau auto "kernel" off 0
setup f-region "$CTL"; gpu f-region 0000:03:00.0 amdgpu
check f-region auto "region" off 0
setup f-region-xe "$CTL"; gpu f-region-xe 0000:00:02.0 xe
check f-region-xe auto "region" off 0
setup f-capacity "$CTL"; gpu f-capacity 0000:03:00.0 amdgpu; rm "$T/f-capacity/cg/dmem.capacity"
check f-capacity auto "capacity" off 0
# the cause goes away, the next boot clears the problem; one GPU's region missing among two still names it
setup f-mode2 "$CTL" "drm/0000:03:00.0/vram 8573157376"; gpu f-mode2 0000:03:00.0 amdgpu
check f-mode2 sometimes "mode" off 0
check f-mode2 auto "" on 0
setup f-two "$CTL" "drm/0000:03:00.0/vram 8573157376"; gpu f-two 0000:03:00.0 amdgpu; gpu f-two 0000:c5:00.0 amdgpu
check f-two auto "region" on 0
echo "drm/0000:c5:00.0/vram 536870912" >>"$T/f-two/cg/dmem.capacity"
check f-two auto "" on 0
# the engine cannot keep it: the unit fails, said
printf 'SPARKY_STEREO_VRAM_BOOST=sometimes\n' >"$T/f-mode/defaults"
SPARKY_STEREO_VRAM_BOOST_ENGINE=false SPARKY_STEREO_VRAM_BOOST_RUN=$T/f-mode/run2 SPARKY_STEREO_VRAM_BOOST_CGROUP=$T/f-mode/cg \
	SPARKY_STEREO_VRAM_BOOST_PCI=$T/f-mode/pci SPARKY_STEREO_VRAM_BOOST_DEFAULTS=$T/f-mode/defaults "$SCRIPT" >"$T/f-mode/out2" 2>&1
s=$?
if [ "$s" = 1 ] && grep -q 'problem mode' "$T/f-mode/out2"; then echo "PASS engine-cannot-keep exit=1 and said"; else echo "FAIL engine-cannot-keep exit=$s"; fails=$((fails + 1)); fi
sparky-stereo-problems clear --all "$PKG" >/dev/null 2>&1
echo "failures: $fails"
exit $((fails > 0))
