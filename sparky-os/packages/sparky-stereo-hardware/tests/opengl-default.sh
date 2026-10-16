#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# Tests the OpenGL stereo default (lib/opengl-default.sh, bin/sparky-stereo-opengl-default and
# share/plasma-env/sparky-stereo-opengl.sh) on fixture sysfs trees.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/lib/opengl-default.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
card() { # card SYS N DRIVER BOOTVGA RENDER(0/1) STATUS...: a DRM card; its render node goes to SYS/dev
	s=$1 n=$2; c=$s/class/drm/card$n; d=$s/devices/pci$n
	mkdir -p "$d/drm/card$n" "$c" "$s/bus/pci/drivers/$3" "$s/dev"; ln -s "$d" "$c/device"
	ln -s "$s/bus/pci/drivers/$3" "$d/driver"; echo "$4" > "$d/boot_vga"
	if [ "$5" = 1 ]; then mkdir -p "$d/drm/renderD$((128 + n))"; : > "$s/dev/renderD$((128 + n))"; fi
	shift 5; i=0
	for st in "$@"; do i=$((i + 1)); mkdir -p "$s/class/drm/card$n-DP-$i"; echo "$st" > "$s/class/drm/card$n-DP-$i/status"; done
}
decide() { opengl_desktop "$1" "$1/dev"; }

s=$T/nv; card $s 0 nvidia 1 1 connected
check "NVIDIA alone" "$(decide $s)" nvidia
check "NVIDIA alone: the card" "$(opengl_desktop_card $s $s/dev)" "card0 nvidia"
s=$T/amd; card $s 0 amdgpu 1 1 connected
check "AMD alone" "$(decide $s)" mesa
s=$T/hybrid; card $s 0 i915 1 1 connected; card $s 1 nvidia 0 1
check "hybrid laptop, the desktop on Intel" "$(decide $s)" mesa
s=$T/dgpu; card $s 0 amdgpu 0 1 disconnected; card $s 1 nvidia 1 1 connected
check "integrated AMD and the NVIDIA card as boot VGA" "$(decide $s)" nvidia
s=$T/bmc; card $s 0 ast 1 0 connected; card $s 1 nvidia 0 1 connected
check "BMC boot VGA and an NVIDIA card with a screen" "$(decide $s)" nvidia
s=$T/nouveau; card $s 0 nouveau 1 1 connected
check "nouveau (Mesa)" "$(decide $s)" mesa
s=$T/none; mkdir -p $s/class/drm $s/dev
check "no card" "$(decide $s)" none
s=$T/nodes; card $s 0 amdgpu 1 1 connected; card $s 1 nvidia 0 1 connected; rm "$s/dev/renderD128"
check "only the NVIDIA render node present (a container given the NVIDIA card)" "$(decide $s)" nvidia

# the writer: the person's choice is kept, --opengl replaces it
run() { _s=$1; shift; SPARKY_STEREO_HARDWARE_LIB=$HERE/lib SPARKY_STEREO_SYSFS=$_s SPARKY_STEREO_DEV=$_s/dev SPARKY_STEREO_OPENGL_CONF=$T/conf/opengl-stereo.conf sh "$HERE/bin/sparky-stereo-opengl-default" "$@" > /dev/null; }
key() { sed -n "s/^$1=//p" "$T/conf/opengl-stereo.conf"; }
run $T/nv
check "written: desktop" "$(key desktop)" nvidia
check "written: card" "$(key card)" card0
check "written: zink by default" "$(key opengl)" zink
run $T/nv --opengl nvidia
check "the person's choice" "$(key opengl)" nvidia
run $T/amd
check "a GPU change rewrites the desktop" "$(key desktop)" mesa
check "and keeps the person's choice" "$(key opengl)" nvidia
run $T/nv --opengl zink
check "back to zink" "$(key opengl)" zink
check "a wrong choice is refused" "$(run $T/nv --opengl other 2>/dev/null; echo $?)" 2

# the session: what a program started from the menu gets
mkdir -p $T/vendors $T/bin; : > $T/vendors/50_mesa.json; : > $T/vendors/10_nvidia.json
printf '#!/bin/sh\necho "${SYSTEMD_BOOT:-true}"\n' > $T/bin/kreadconfig6; chmod +x $T/bin/kreadconfig6
session() { (env -i PATH="$T/bin:/usr/bin:/bin" SPARKY_STEREO_OPENGL_CONF=$T/conf/opengl-stereo.conf SPARKY_STEREO_EGL_VENDORS=$T/vendors "$@" \
	sh -c '. "$0"; echo "${SPARKY_STEREO_OPENGL:-}|${__EGL_VENDOR_LIBRARY_FILENAMES:-}|${__GLX_VENDOR_LIBRARY_NAME:-}|${MESA_LOADER_DRIVER_OVERRIDE:-}|${LIBGL_KOPPER_DISABLE:-}|${GL_STEREO_NVIDIA_OPENGL:-}"' \
	"$HERE/share/plasma-env/sparky-stereo-opengl.sh"); }
zink="zink|$T/vendors/50_mesa.json:$T/vendors/10_nvidia.json|mesa|zink|1|zink"
run $T/nv
check "NVIDIA desktop, zink" "$(session)" "$zink"
run $T/amd
check "Mesa desktop: nothing" "$(session)" "|||||"
run $T/nv --opengl nvidia
check "NVIDIA desktop, NVIDIA's own OpenGL" "$(session)" "|||||nvidia"
run $T/nv --opengl zink
check "KWin started without systemd: nothing" "$(session SYSTEMD_BOOT=false)" "|||||zink"
check "the person's own EGL vendor list is kept" "$(session __EGL_VENDOR_LIBRARY_FILENAMES=/x.json)" "|/x.json||||zink"
rm $T/vendors/10_nvidia.json
check "NVIDIA's EGL vendor missing: nothing" "$(session)" "|||||zink"
: > $T/vendors/10_nvidia.json

# KWin drops every variable the session script sets
unset_line=$(sed -n 's/^UnsetEnvironment=//p' "$HERE/share/systemd-user/sparky-stereo-opengl.conf")
for v in $(grep -o 'export [A-Z_]*=' "$HERE/share/plasma-env/sparky-stereo-opengl.sh" | sed 's/export //; s/=//' | sort -u); do
	[ "$v" = GL_STEREO_NVIDIA_OPENGL ] && continue
	case " $unset_line " in *" $v "*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); echo "FAIL KWin keeps $v" ;; esac
done
echo "opengl-default: $pass passed, $fail failed"
[ "$fail" = 0 ]
