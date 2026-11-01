#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/01
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
LOCK=sparky-stereo-nvidia-driver-lock
REPO=sparky-stereo-cuda-repo
DRIVER_LINE='DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install nvidia-driver=615.71.09-2 nvidia-kernel-open-dkms-stereo3d libnvcuvid1=615.71.09-2 nvidia-vaapi-driver'
installed_packages=
apt-cache() { [[ ${missing_module:-0} == 0 ]] || return 1; printf '%s\n' 'Package: nvidia-kernel-open-dkms-stereo3d' "Version: ${module_version:-615.71.09-2+stereo3d4}"; }
curl() { echo "curl $*" >>"$calls"; return 1; }
dpkg-query() { [[ " $installed_packages " != *" ${*: -1} "* ]] || printf 'ii '; }
dpkg() { echo "dpkg $*" >>"$calls"; }
env() {
	echo "$*" >>"$calls"
	[[ $* != *"install $LOCK"* || ${fail_policy:-0} == 0 ]] || return 1
	[[ $* != *--simulate* || ${fail_preflight:-0} == 0 ]] || return 1
	[[ $* != *install\ nvidia-driver=* || $* == *--simulate* || ${fail_install:-0} == 0 ]] || return 1
}
# a check that fails the test when the command succeeds (bash's set -e ignores a command inverted with !)
refute() { if "$@"; then echo "FAIL: $*"; exit 1; fi; }
line_of() { grep -nFx "$1" "$calls" | head -n1 | cut -d: -f1; }
no_hand_files() { [[ ! -e "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources" && ! -e "$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda" && ! -e "$ROOT/etc/apt/keyrings/sparky-stereo-cuda.gpg" ]]; }
missing_module=1
: >"$calls"
setup_nvidia
refute grep -q install "$calls"
missing_module=0
: >"$calls"
setup_nvidia
policy_line=$(line_of "DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install $LOCK $REPO")
update_line=$(line_of 'DEBIAN_FRONTEND=noninteractive apt-get -y update')
simulate_line=$(line_of "${DRIVER_LINE/ install / --simulate install }")
driver_line=$(line_of "$DRIVER_LINE")
[[ -n $policy_line && -n $update_line && -n $simulate_line && -n $driver_line ]]
((policy_line < update_line && update_line < simulate_line && simulate_line < driver_line))
refute grep -q '^curl' "$calls"
no_hand_files
echo 'PASS NVIDIA: the driver lock and the CUDA repository package first, in their own transaction, then the index, the preflight and the exact driver; no file written by hand, no download'
: >"$calls"
installed_packages="$LOCK $REPO"
setup_nvidia
refute grep -q "install $LOCK" "$calls"
grep -Fxq "$DRIVER_LINE" "$calls"
installed_packages=
echo 'PASS NVIDIA: an installed lock and repository package are not installed again'
mkdir -p "$ROOT/etc/apt/sources.list.d"
printf 'Types: deb\nURIs: https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/\nSuites: /\nArchitectures: amd64\nSigned-By: /etc/apt/keyrings/sparky-stereo-cuda.gpg\n' >"$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
printf '# deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/ /\n' >"$ROOT/etc/apt/sources.list.d/commented.list"
: >"$calls"
setup_nvidia >"$T/log"
grep -Fxq "DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install $LOCK $REPO" "$calls"
refute grep -q 'already configured' "$T/log"
echo 'PASS NVIDIA: the source the image or an older setup wrote, and a commented line, are not a repository of the person'"'"'s'
printf 'deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/ /\n' >"$ROOT/etc/apt/sources.list.d/cuda-debian13-x86_64.list"
: >"$calls"
setup_nvidia >"$T/log"
grep -Fxq "DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install $LOCK" "$calls"
refute grep -q "install $LOCK $REPO" "$calls"
grep -Fq "NVIDIA's CUDA repository is already configured in /etc/apt/sources.list.d/cuda-debian13-x86_64.list; kept as it is" "$T/log"
grep -Fxq "$DRIVER_LINE" "$calls"
rm -f "$ROOT/etc/apt/sources.list.d/cuda-debian13-x86_64.list" "$ROOT/etc/apt/sources.list.d/commented.list" "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
echo 'PASS NVIDIA: a CUDA repository the person set up is kept; only the driver lock is added before the driver'
fail_policy=1
: >"$calls"
setup_nvidia >"$T/log"
grep -Fxq "dpkg --purge $LOCK $REPO" "$calls"
refute grep -q -- '--simulate' "$calls"
grep -q '^FALLBACK' "$T/log"
fail_policy=0
fail_preflight=1
: >"$calls"
setup_nvidia >"$T/log"
grep -Fxq "dpkg --purge $LOCK $REPO" "$calls"
refute grep -Fxq "$DRIVER_LINE" "$calls"
grep -q 'FALLBACK NVIDIA preflight failed' "$T/log"
installed_packages="$LOCK $REPO"
: >"$calls"
setup_nvidia >"$T/log"
refute grep -q 'dpkg --purge' "$calls"
installed_packages=
fail_preflight=0
echo 'PASS NVIDIA: a failed policy install or preflight purges what this run installed and nothing else'
# The userspace driver follows the module's version, whatever NVIDIA version that is.
: >"$calls"
module_version=620.10.01-1+stereo3d1
setup_nvidia
grep -Fxq 'DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install nvidia-driver=620.10.01-1 nvidia-kernel-open-dkms-stereo3d libnvcuvid1=620.10.01-1 nvidia-vaapi-driver' "$calls"
# The published module carries Lean Code's mark after ours (615.71.09-2+stereo3d7+lc1).
: >"$calls"
module_version=615.71.09-2+stereo3d7+lc1
setup_nvidia
grep -Fxq "$DRIVER_LINE" "$calls"
module_version=615.71.09-2
: >"$calls"
setup_nvidia
refute grep -q 'install nvidia-driver' "$calls"
module_version=615.71.09-2+lc1
: >"$calls"
setup_nvidia
refute grep -q 'install nvidia-driver' "$calls"
module_version=615.71.09-2+stereo3d4
echo 'PASS NVIDIA driver version follows the module (a new version, a Lean Code build, and a module without our suffix is refused)'
fail_install=1
if setup_nvidia; then echo 'FAIL NVIDIA transaction failure hidden'; exit 1; fi
echo 'PASS missing module, policy install, preflight rollback and transaction error paths'

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
