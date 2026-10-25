#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/25
# The boot decision against made-up sysfs trees: each case builds a cgroup root and PCI devices with their drivers, runs
# the detector with its paths pointed there and compares decision= with the expected one. Exit 1 on any mismatch.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
DETECT=${DETECT:-$HERE/bin/sparky-stereo-vram-boost}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
gpu() { # gpu CASE ADDRESS DRIVER [vendor]
	mkdir -p "$T/$1/pci/$2" "$T/$1/drivers/$3"
	ln -s "$T/$1/drivers/$3" "$T/$1/pci/$2/driver"
	[ "${4:-}" = vendor ] && echo samsung >"$T/$1/pci/$2/mem_info_vram_vendor"
	return 0
}
setup() { # setup CASE CONTROLLERS [REGION...]
	local c=$1 ctl=$2; shift 2
	mkdir -p "$T/$c/cg" "$T/$c/pci"
	echo "$ctl" >"$T/$c/cg/cgroup.controllers"
	: >"$T/$c/cg/dmem.capacity"
	for r in "$@"; do echo "$r" >>"$T/$c/cg/dmem.capacity"; done
}
run() { # run CASE MODE EXPECTED
	local c=$1 mode=$2 want=$3
	printf 'SPARKY_STEREO_VRAM_BOOST=%s\n' "$mode" >"$T/$c/defaults"
	SPARKY_STEREO_VRAM_BOOST_RUN=$T/$c/run SPARKY_STEREO_VRAM_BOOST_CGROUP=$T/$c/cg SPARKY_STEREO_VRAM_BOOST_PCI=$T/$c/pci \
		SPARKY_STEREO_VRAM_BOOST_DEFAULTS=$T/$c/defaults SPARKY_STEREO_VRAM_BOOST_WAIT=${WAIT:-2} \
		"$DETECT" >/dev/null
	local got enabled=no
	got=$(sed -n 's/^decision=//p' "$T/$c/run/state")
	[ -e "$T/$c/run/enabled" ] && enabled=yes
	local expect_enabled=no
	[ "$want" = on ] && expect_enabled=yes
	if [ "$got" = "$want" ] && [ "$enabled" = "$expect_enabled" ]; then
		echo "PASS $c mode=$mode decision=$got enabled=$enabled ($(sed -n 's/^reason=//p' "$T/$c/run/state"))"
	else
		echo "FAIL $c mode=$mode decision=$got (want $want) enabled=$enabled"; fails=$((fails+1))
	fi
}
CTL="cpuset cpu io memory hugetlb pids rdma misc dmem"
setup no-dmem "cpuset cpu io memory hugetlb pids rdma misc"; gpu no-dmem 0000:03:00.0 amdgpu vendor; run no-dmem auto off; run no-dmem amd-dgpu off; run no-dmem yes off
setup no-region "$CTL"; run no-region auto off; run no-region amd-dgpu off; run no-region yes off
setup amd-dgpu "$CTL" "drm/0000:03:00.0/vram 8573157376"; gpu amd-dgpu 0000:03:00.0 amdgpu vendor
run amd-dgpu auto on; run amd-dgpu amd-dgpu on; run amd-dgpu yes on; run amd-dgpu no off; run amd-dgpu sometimes off
setup amd-apu "$CTL" "drm/0000:c5:00.0/vram 536870912"; gpu amd-apu 0000:c5:00.0 amdgpu; run amd-apu auto on; run amd-apu amd-dgpu off; run amd-apu yes on
setup intel-xe "$CTL" "drm/0000:00:02.0/vram0 4294967296"; gpu intel-xe 0000:00:02.0 xe; run intel-xe auto on; run intel-xe amd-dgpu off; run intel-xe yes on
setup nouveau "$CTL" "drm/0000:01:00.0/vram 6442450944"; gpu nouveau 0000:01:00.0 nouveau vendor; run nouveau auto on; run nouveau amd-dgpu off; run nouveau yes on
setup nvidia-amd "$CTL" "drm/0000:03:00.0/vram 8573157376"
gpu nvidia-amd 0000:01:00.0 nvidia vendor; gpu nvidia-amd 0000:03:00.0 amdgpu vendor; run nvidia-amd auto on
setup nvidia-only "$CTL"; gpu nvidia-only 0000:01:00.0 nvidia vendor; run nvidia-only auto off; run nvidia-only amd-dgpu off; run nvidia-only yes off
# amdgpu bound but its region registered two seconds after the detector starts: it waits (WAIT seconds) and turns on
setup late "$CTL"; gpu late 0000:03:00.0 amdgpu vendor
( sleep 2; echo "drm/0000:03:00.0/vram 8573157376" >>"$T/late/cg/dmem.capacity" ) &
WAIT=6 run late auto on
wait
echo "failures: $fails"
exit $((fails > 0))
