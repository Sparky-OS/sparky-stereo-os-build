#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/01
set -euo pipefail
[[ -e /.dockerenv ]] || exit 1
HARDWARE_ACTIONS_FILE=${HARDWARE_ACTIONS:-/usr/lib/sparky-stereo-hardware/actions.sh}
source "$HARDWARE_ACTIONS_FILE"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
# the strings, error messages included: the source tree's lang/ or the installed package's; neither is a test failure
if [[ -r $(dirname "$HARDWARE_ACTIONS_FILE")/../lang/en ]]; then
	SHARE=$(cd "$(dirname "$HARDWARE_ACTIONS_FILE")/../lang" && pwd)
elif [[ -r /usr/share/sparky/sparky-stereo-hardware/en ]]; then
	SHARE=/usr/share/sparky/sparky-stereo-hardware
else
	echo "FAIL: no strings next to $HARDWARE_ACTIONS_FILE and none installed"
	exit 1
fi
LANGUAGES=(en pl pt_BR fr de ja ko zh_CN zh_TW)
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
dpkg() { echo "dpkg $*" >>"$calls"; [[ ${fail_purge:-0} == 0 ]]; }
env() {
	echo "$*" >>"$calls"
	[[ $* != *"install $LOCK"* || ${fail_policy:-0} == 0 ]] || return 1
	[[ $* != *'apt-get -y update'* || ${fail_update:-0} == 0 ]] || return 1
	[[ $* != *--simulate* || ${fail_preflight:-0} == 0 ]] || return 1
	[[ $* != *install\ nvidia-driver=* || $* == *--simulate* || ${fail_install:-0} == 0 ]] || return 1
}
# a check that fails the test when the command succeeds (bash's set -e ignores a command inverted with !)
refute() { if "$@"; then echo "FAIL: $*"; exit 1; fi; }
line_of() { grep -nFx "$1" "$calls" | head -n1 | cut -d: -f1; }
no_hand_files() { [[ ! -e "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources" && ! -e "$ROOT/etc/apt/preferences.d/91sparky-stereo-cuda" && ! -e "$ROOT/etc/apt/keyrings/sparky-stereo-cuda.gpg" ]]; }
# fails_with PATTERN COMMAND...: the command returns non-zero, prints an ERROR line matching PATTERN, and says nothing of a
# fallback (since 0.1.16 none exists: Daniel, 2026-11-01, "nothing we do should silently fail or have a fall back")
fails_with() {
	local pattern=$1; shift
	if "$@" >"$T/out"; then echo "FAIL: $* succeeded"; cat "$T/out"; exit 1; fi
	grep -Eq "^ERROR $pattern" "$T/out" || { echo "FAIL: no ERROR line matching '$pattern' from $*"; cat "$T/out"; exit 1; }
	refute grep -qiE 'fallback|nouveau firmware installed' "$T/out"
}
refute grep -nE 'FALLBACK|UNSUPPORTED' "$HARDWARE_ACTIONS_FILE"
echo 'PASS no FALLBACK or UNSUPPORTED message is left in actions.sh'
missing_module=1
: >"$calls"
fails_with 'NVIDIA: apt finds no nvidia-kernel-open-dkms-stereo3d' setup_nvidia
grep -Fq -- '--nvidia nouveau' "$T/out"
refute grep -q install "$calls"
missing_module=0
echo 'PASS NVIDIA: a missing module stops the setup with what failed, why and what to do (nouveau only as the person'"'"'s choice), and installs nothing'
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
# sparky-stereo-cuda-repo itself keeps the person's source (its postinst writes none of its own then) and adds its pins,
# which go by origin; so both policy packages come, and the setup says why the person's source stays
grep -Fxq "DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-suggests install $LOCK $REPO" "$calls"
grep -Fq "NVIDIA's CUDA repository is already configured in /etc/apt/sources.list.d/cuda-debian13-x86_64.list; sparky-stereo-cuda-repo keeps that source and adds the edition's pins" "$T/log"
grep -Fxq "$DRIVER_LINE" "$calls"
rm -f "$ROOT/etc/apt/sources.list.d/cuda-debian13-x86_64.list" "$ROOT/etc/apt/sources.list.d/commented.list" "$ROOT/etc/apt/sources.list.d/sparky-stereo-cuda.sources"
echo 'PASS NVIDIA: a CUDA repository the person set up is kept and named; the lock and the repository package (for its pins) come before the driver'
fail_policy=1
: >"$calls"
fails_with "NVIDIA: $LOCK $REPO could not be installed" setup_nvidia
grep -Fxq "dpkg --purge $LOCK $REPO" "$calls"
refute grep -q -- '--simulate' "$calls"
fail_policy=0
fail_update=1
: >"$calls"
fails_with 'NVIDIA: apt could not read the repositories' setup_nvidia
grep -Fxq "dpkg --purge $LOCK $REPO" "$calls"
refute grep -q -- '--simulate' "$calls"
fail_update=0
fail_preflight=1
: >"$calls"
fails_with "NVIDIA: apt cannot install NVIDIA's driver 615.71.09-2" setup_nvidia
grep -Fxq "dpkg --purge $LOCK $REPO" "$calls"
refute grep -Fxq "$DRIVER_LINE" "$calls"
installed_packages="$LOCK $REPO"
: >"$calls"
fails_with "NVIDIA: apt cannot install NVIDIA's driver" setup_nvidia
refute grep -q 'dpkg --purge' "$calls"
installed_packages=
fail_purge=1
: >"$calls"
fails_with "NVIDIA: purging $LOCK $REPO again failed too" setup_nvidia
fail_purge=0
fail_preflight=0
echo 'PASS NVIDIA: a failed policy install, index update or preflight stops the setup, says so, and purges what this run installed and nothing else'
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
for module_version in 615.71.09-2 615.71.09-2+lc1; do
	: >"$calls"
	fails_with "NVIDIA: the module's version ${module_version//+/\\+} has no \\+stereo3dN suffix" setup_nvidia
	refute grep -q 'install' "$calls"
done
module_version=615.71.09-2+stereo3d4
echo 'PASS NVIDIA driver version follows the module (a new version, a Lean Code build); a module without our suffix stops the setup and says so'
fail_install=1
fails_with 'NVIDIA: the driver.s installation stopped part way' setup_nvidia
echo 'PASS missing module, policy install, index update, preflight, purge and transaction error paths each fail visibly'

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

# Rig drivers: every refusal says why.
uname() { echo "${kernel_name:-7.3.1-stereo3d14}"; }
fails_with 'Wheel driver evdi-dkms: not one of the wheel drivers' setup_rig_driver evdi-dkms
kernel_name='bad name'
fails_with 'Wheel driver hid-tmff2-dkms: the running kernel.s name' setup_rig_driver hid-tmff2-dkms
kernel_name=
fail_preflight=1
fails_with 'Wheel driver hid-tmff2-dkms: apt cannot install it with linux-headers-7.3.1-stereo3d14' setup_rig_driver hid-tmff2-dkms
fail_preflight=0
echo 'PASS rig drivers: an unknown package, an unusable kernel name and a failed preflight each fail with their reason'
# AMD power: an action power-profiles-daemon does not offer is an error, not a quiet skip; the other action still runs.
powerprofilesctl() {
	echo "powerprofilesctl $*" >>"$calls"
	if [[ $1 == list-actions ]]; then
		printf 'Name: amdgpu_dpm\nEnabled: %s\n\n' "$( [[ -e $T/dpm-on ]] && echo True || echo False)"
	elif [[ $1 == configure-action ]]; then
		: >"$T/dpm-on"
	fi
}
: >"$calls"
fails_with 'AMD power: power-profiles-daemon offers no action amdgpu_panel_power' setup_amdgpu amdgpu_panel_power amdgpu_dpm
grep -q 'VERIFIED PPD action amdgpu_dpm enabled' "$T/out"
echo 'PASS AMD power: an action the machine does not offer fails visibly, and the offered one is still enabled'
# The plan window: only its buttons are answers; its own failure never counts as one.
[[ $(plan_answer 0) == edition && $(plan_answer 2) == nouveau && $(plan_answer 1) == cancel && $(plan_answer 252) == cancel ]]
for code in 3 70 127 255; do [[ $(plan_answer $code) == window-failed ]]; done
echo 'PASS the plan window: install, keep nouveau, cancel, and a failed window told apart'
# The error messages: every one the code uses exists in the nine languages, with the English message's %s count and no
# other printf directive, and the window's lines in the person's language.
code_files=("$HARDWARE_ACTIONS_FILE")
for f in "$(dirname "$HARDWARE_ACTIONS_FILE")/../bin/sparky-stereo-hardware" /usr/bin/sparky-stereo-hardware; do
	if [[ -r $f ]]; then code_files+=("$f"); fi
done
[[ ${#code_files[@]} -ge 2 ]] || { echo 'FAIL: sparky-stereo-hardware itself not found next to actions.sh or installed'; exit 1; }
used=$(grep -ohE '\berr [0-9]+' "${code_files[@]}" | awk '{print $2}' | sort -un)
[[ -n $used ]] || { echo 'FAIL: no err call found'; exit 1; }
# count_of PATTERN TEXT: how often PATTERN occurs in TEXT
count_of() { awk -v pattern="$1" -v text="$2" 'BEGIN {print gsub(pattern, "", text)}'; }
for id in $used 29; do
	en_text=$(source "$SHARE/en"; v=LOCAL$id; printf '%s' "${!v:-}")
	[[ -n $en_text ]] || { echo "FAIL: message $id has no English text"; exit 1; }
	en_count=$(count_of '%s' "$en_text")
	for language in "${LANGUAGES[@]}"; do
		text=$(source "$SHARE/$language"; v=LOCAL$id; printf '%s' "${!v:-}")
		[[ -n $text ]] || { echo "FAIL: message $id is missing in $language"; exit 1; }
		[[ $language == en || $text != "$en_text" ]] || { echo "FAIL: message $id in $language is the English text"; exit 1; }
		[[ $(count_of '%s' "$text") == "$en_count" ]] || { echo "FAIL: message $id in $language has another %s count"; exit 1; }
		[[ $(count_of '%' "$text") == "$en_count" ]] || { echo "FAIL: message $id in $language has a printf directive other than %s"; exit 1; }
		refute grep -q '\\' <<<"$text"
	done
done
for language in "${LANGUAGES[@]}"; do
	text=$(source "$SHARE/$language"; printf '%s' "$LOCAL6")
	refute grep -qi 'english\|anglais\|ingl\|angielsk\|englisch\|英語\|영어\|英文\|英语' <<<"$text"
done
echo "PASS the error messages $(tr '\n' ' ' <<<"$used")and the nouveau choice exist in the nine languages with the English %s count"
# The end of a run: the list of ERROR lines in English and exit 1, and the same list in a window in the person's language
# when the menu started it.
yad() {
	local a
	echo "yad $*" >>"$calls"
	for a; do if [[ $a == --filename=* ]]; then cp "${a#--filename=}" "$T/window"; fi; done
}
: >"$WORK/errors"
err 47 'nvidia-settings' >"$T/out"
grep -Fxq 'ERROR nvidia-settings could not be installed (apt failed, see the log); fix the apt error and run Hardware Setup again' "$T/out"
log 'NOTE not an error' >/dev/null
err 40 'nvidia-kernel-open-dkms-stereo3d' >/dev/null
[[ $(wc -l <"$WORK/errors") == 2 ]]
: >"$calls"
if finish_run "$T/run.log" 1 >"$T/out"; then echo 'FAIL a run with errors ended with status 0'; exit 1; fi
grep -Fxq 'ERROR nvidia-settings could not be installed (apt failed, see the log); fix the apt error and run Hardware Setup again' "$T/out"
grep -Fq "ERROR NVIDIA: apt finds no nvidia-kernel-open-dkms-stereo3d, the edition's NVIDIA module with HDMI 3D" "$T/out"
grep -Fq 'or keep nouveau, without HDMI 3D, as your own choice: the plan window'"'"'s button “Install matched support, keep nouveau”, or sparky-stereo-hardware --nvidia nouveau' "$T/out"
refute grep -q '^yad' "$calls"
refute grep -q '@NOUVEAU@\|@BUTTON@\|^message ' "$T/out"
LOCALE_FILE=$T/locale
printf 'LANG=pt_BR.UTF-8\n' >"$LOCALE_FILE"
: >"$calls"
if SPARKY_STEREO_HARDWARE_GUI=1 DISPLAY=:9 finish_run "$T/run.log" 1 >"$T/out"; then echo 'FAIL a GUI run with errors ended with status 0'; exit 1; fi
grep -q '^yad --text-info' "$calls"
grep -Fq 'Configuração de hardware: algumas etapas falharam' "$calls"
grep -Fxq 'Estas etapas não foram feitas, e nada foi colocado no lugar delas. Cada linha diz o que falhou, por que e o que fazer:' "$T/window"
grep -Fxq 'Não foi possível instalar nvidia-settings (o apt falhou, veja o registro); corrija o erro do apt e rode a Configuração de hardware de novo' "$T/window"
grep -Fq 'NVIDIA: o apt não encontra nvidia-kernel-open-dkms-stereo3d, o módulo NVIDIA da edição com HDMI 3D' "$T/window"
grep -Fq 'o botão “Instalar suporte ao hardware detectado, manter o nouveau” da janela do plano' "$T/window"
refute grep -q 'ERROR\|could not be installed\|@NOUVEAU@\|@BUTTON@' "$T/window"
# the log keeps English for support, also in a GUI run
grep -Fxq 'ERROR nvidia-settings could not be installed (apt failed, see the log); fix the apt error and run Hardware Setup again' "$T/out"
for language in ja zh_TW; do
	case $language in ja) printf 'LANG=ja_JP.UTF-8\n' ;; zh_TW) printf 'LANG=zh_TW.UTF-8\n' ;; esac >"$LOCALE_FILE"
	if SPARKY_STEREO_HARDWARE_GUI=1 DISPLAY=:9 finish_run "$T/run.log" 1 >/dev/null; then echo "FAIL a GUI run in $language ended with status 0"; exit 1; fi
	expected=$(source "$SHARE/$language"; printf "$LOCAL47" nvidia-settings)
	grep -Fxq "$expected" "$T/window"
done
echo 'PASS the end of a run: its errors listed in English with exit 1, and a window in the person'"'"'s language (pt_BR, ja, zh_TW) when the menu started it'
# a run that failed without a message of its own still says so, in the window too
: >"$WORK/errors"
printf 'LANG=de_DE.UTF-8\n' >"$LOCALE_FILE"
if SPARKY_STEREO_HARDWARE_GUI=1 DISPLAY=:9 finish_run "$T/run.log" 1 >"$T/out"; then echo 'FAIL a failed run without messages ended with status 0'; exit 1; fi
grep -Fxq "ERROR A step failed without an error message of its own; the log $T/run.log shows which" "$T/out"
grep -Fxq "Ein Schritt ist ohne eigene Fehlermeldung fehlgeschlagen; das Protokoll $T/run.log zeigt, welcher" "$T/window"
echo 'PASS a failed run without a message of its own says so, in English and in the window'
: >"$WORK/errors"
finish_run "$T/run.log" 0 >"$T/out"
grep -q 'finished with no errors' "$T/out"
echo 'PASS a run without errors ends with status 0'
