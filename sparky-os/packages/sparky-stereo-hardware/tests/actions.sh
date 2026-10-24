#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
set -euo pipefail
[[ -e /.dockerenv ]] || exit 1
source "${HARDWARE_ACTIONS:-/usr/lib/sparky-stereo-hardware/actions.sh}"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
ROOT=$T/root
WORK=$T/work
mkdir -p "$ROOT" "$WORK"
: >"$WORK/plan"
calls=$T/calls
: >"$calls"

sensors-detect() {
	[[ $* == --auto ]] || return 1
	cat <<'EOF'
To load everything that is needed, add this to /etc/modules:
#----cut here----
# Chip drivers
coretemp
nct6775
#----cut here----
EOF
}
modprobe() {
	echo "modprobe $*" >>"$calls"
	[[ ${fail_load:-0} == 0 ]] || return 1
	mkdir -p "$ROOT/sys/module/${1//-/_}"
}
sensors() {
	[[ ${no_readings:-0} == 0 ]] || { echo 'No sensors found!'; return 1; }
	echo 'temp1_input: 42.000'
}
setup_sensors
printf 'coretemp\nnct6775\n' >"$T/expected"
cmp "$T/expected" "$ROOT/etc/modules-load.d/sparky-stereo-sensors.conf"
setup_sensors
cmp "$T/expected" "$ROOT/etc/modules-load.d/sparky-stereo-sensors.conf"
echo 'PASS sensor recommendations persisted, modules loaded, readings checked; repeat does not duplicate'
fail_load=1
if setup_sensors; then echo 'FAIL module load failure hidden'; exit 1; fi
fail_load=0
no_readings=1
if setup_sensors; then echo 'FAIL absent readings hidden'; exit 1; fi
no_readings=0
echo 'PASS sensor load/readings failure propagation'

mkdir -p "$ROOT/usr/lib/firmware/updates"
if setup_creative; then echo 'FAIL missing firmware accepted'; exit 1; fi
for file in ctefx.bin ctefx-desktop.bin ctefx-r3di.bin ctspeq.bin; do
	printf 'test' >"$ROOT/usr/lib/firmware/updates/$file"
done
setup_creative
grep -Fxq 'options snd_hda_intel enable_msi=1' "$ROOT/etc/modprobe.d/sparky-stereo-creative.conf"
echo 'PASS Creative requires four blobs and writes the real kernel parameter'

# The commands below are doubles. No actual repository or driver is changed.
mkdir -p "$T/key/DEBIAN" "$T/key/usr/share/keyrings"
printf 'Package: test-cuda-key\nVersion: 1\nArchitecture: all\nMaintainer: Test <test@example.invalid>\nDescription: Fixture\n' >"$T/key/DEBIAN/control"
printf 'fixture public key\n' >"$T/key/usr/share/keyrings/cuda-archive-keyring.gpg"
dpkg-deb --root-owner-group -b "$T/key" "$T/key.deb" >/dev/null
CUDA_KEY_SHA256=$(sha256sum "$T/key.deb" | cut -d' ' -f1)
apt-cache() { [[ ${missing_module:-0} == 0 ]] || return 1; printf '%s\n' 'Package: nvidia-kernel-open-dkms-stereo3d' "Version: ${module_version:-615.71.09-2+stereo3d4}"; }
curl() {
	[[ ${bad_download:-0} == 0 ]] || return 22
	[[ $* == *cuda-keyring_1.1-1_all.deb* ]] || return 1
	cp "$T/key.deb" "${@: -1}"
}
env() {
	echo "$*" >>"$calls"
	[[ $* != *--simulate* || ${fail_preflight:-0} == 0 ]] || return 1
	[[ $* != *install* || $* == *--simulate* || ${fail_install:-0} == 0 ]] || return 1
}
missing_module=1
setup_nvidia
[[ ! -e "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources" ]]
missing_module=0
bad_download=1
setup_nvidia
[[ ! -e "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources" ]]
bad_download=0
saved=$CUDA_KEY_SHA256
CUDA_KEY_SHA256=0000000000000000000000000000000000000000000000000000000000000000
setup_nvidia
[[ ! -e "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources" ]]
CUDA_KEY_SHA256=$saved
fail_preflight=1
setup_nvidia
[[ ! -e "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources" ]]
fail_preflight=0
setup_nvidia
grep -Fxq 'Pin-Priority: 1002' "$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda"
grep -Fxq 'Pin: origin developer.download.nvidia.com' "$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda"
grep -Fxq 'Signed-By: /etc/apt/keyrings/sparky-stereo-cuda.gpg' "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
cmp "$T/key/usr/share/keyrings/cuda-archive-keyring.gpg" "$ROOT/etc/apt/keyrings/sparky-stereo-cuda.gpg"
grep -Fxq 'DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install nvidia-driver=615.71.09-2 nvidia-kernel-open-dkms-stereo3d libnvcuvid1=615.71.09-2 nvidia-vaapi-driver' "$calls"
echo 'PASS NVIDIA exact userspace, explicit edition module, key archive verification, Signed-By and origin pin'
# The userspace driver follows the module's version, whatever NVIDIA version that is.
: >"$calls"
module_version=620.10.01-1+stereo3d1
setup_nvidia
grep -Fxq 'DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install nvidia-driver=620.10.01-1 nvidia-kernel-open-dkms-stereo3d libnvcuvid1=620.10.01-1 nvidia-vaapi-driver' "$calls"
module_version=615.71.09-2
: >"$calls"
setup_nvidia
! grep -q 'install nvidia-driver' "$calls"
module_version=615.71.09-2+stereo3d4
echo 'PASS NVIDIA driver version follows the module (a new version, and a module without the suffix is refused)'
printf 'previous policy\n' >"$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda"
fail_preflight=1
setup_nvidia
grep -Fxq 'previous policy' "$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda"
fail_preflight=0
fail_install=1
if setup_nvidia; then echo 'FAIL NVIDIA transaction failure hidden'; exit 1; fi
echo 'PASS missing module, network, checksum, preflight rollback and transaction error paths'

printf 'action\tnvidia-runtime-pm\n' >"$WORK/plan"
if setup_nvidia; then echo 'FAIL NVIDIA failed transaction accepted for laptop'; exit 1; fi
[[ ! -e "$ROOT/etc/modprobe.d/sparky-stereo-nvidia-runtime-pm.conf" ]]
fail_install=0
setup_nvidia
grep -Fxq 'options nvidia NVreg_DynamicPowerManagement=0x02' "$ROOT/etc/modprobe.d/sparky-stereo-nvidia-runtime-pm.conf"
cp "$ROOT/etc/udev/rules.d/80-sparky-stereo-nvidia-runtime-pm.rules" "$T/expected-runtime-rules"
setup_nvidia
cmp "$T/expected-runtime-rules" "$ROOT/etc/udev/rules.d/80-sparky-stereo-nvidia-runtime-pm.rules"
[[ $(grep -c '^ACTION=="bind".*DRIVER=="nvidia"' "$T/expected-runtime-rules") == 2 ]]
[[ $(grep -c '^ACTION=="unbind"' "$T/expected-runtime-rules") == 2 ]]
echo 'PASS laptop RTD3 requires a successful driver transaction and repeats without duplicating rules'
