#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# NVIDIA's driver only where an NVIDIA graphics card is (ORDER 675): the card's step and nvidia-i386 on sysfs fixtures,
# with doubles for apt-get, apt-cache, dpkg-query, dpkg, busctl and Hardware Setup; the edition's real engine keeps and
# clears. The real apt on the real packages is the container proof beside it. Run as root in a throwaway container.
#   nvidia-card.sh PATH/TO/sparky-stereo-hardware-recipe
set -u
[ -e /.dockerenv ] || { echo "run in a container" >&2; exit 2; }
P=$(cd "${1:?the recipe folder}" && pwd)
T=$(mktemp -d /tmp/nvidia-card-test.XXXXXX) || exit 2
trap 'rm -rf "${T:?}"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }
[ ! -e "$P/bin/sparky-stereo-nvidia-card" ] || install -D -m 755 "$P/bin/sparky-stereo-nvidia-card" /usr/lib/sparky-stereo-hardware/nvidia-card
install -D -m 755 "$P/bin/sparky-stereo-nvidia-i386" /usr/lib/sparky-stereo-hardware/nvidia-i386
sparky-stereo-problems catalog sparky-stereo-hardware "$P/problems-lang" "$T/cat" --subject LOCAL9=LOCAL5 >/dev/null 2>&1
export SPARKY_STEREO_PROBLEMS_CATALOG=$T/cat:/usr/lib/systemd/catalog SPARKY_STEREO_ROOT=$T/root
mkdir -p "$T/bin" "$T/root"
# the doubles: one state folder; apt-get purge really takes the packages out of "installed"
cat > "$T/bin/dpkg-query" <<FAKE
#!/bin/bash
fmt=; names=()
while ((\$#)); do case \$1 in -W) ;; -f) shift; fmt=\$1 ;; *) names+=("\$1") ;; esac; shift; done
for n in "\${names[@]}"; do
	while IFS=\$'\t' read -r pkg version; do
		base=\${pkg%%:*}
		arch=amd64; [[ \$pkg == *:i386 ]] && arch=i386
		[[ \$base == "\${n%%:*}" ]] || continue
		[[ \$n != *:* || \${n#*:} == "\$arch" ]] || continue
		case \$fmt in
		*binary:Package*) printf '%s\tii \n' "\$pkg" ;;
		*Package*Architecture*) printf '%s:%s\tii \t%s\n' "\$base" "\$arch" "\$version" ;;
		*) printf 'ii \n' ;;
		esac
	done < $T/installed
done
FAKE
cat > "$T/bin/apt-get" <<FAKE
#!/bin/bash
echo "apt-get \$*" >> $T/apt.calls
case " \$* " in
*" check "*) exit 0 ;;
*" autoremove "*) sed 's/^/Remv /; s/\$/ [1]/' $T/unneeded; exit 0 ;;
esac
pk=(); sim=0; seen=0
for a in "\$@"; do case \$a in -s|--simulate) sim=1 ;; purge) seen=1 ;; -*) ;; *) ((seen)) && pk+=("\$a") ;; esac; done
if ((sim)); then
	for p in "\${pk[@]}" \$(cat $T/also 2>/dev/null); do echo "Purg \$p [1]"; done
	exit 0
fi
[ -e $T/purge.fail ] && { echo "E: dpkg was interrupted"; exit 100; }
for p in "\${pk[@]}"; do grep -v -P "^\Q\$p\E\t" $T/installed > $T/installed.new; mv $T/installed.new $T/installed; done
[ -e $T/unneeded-after ] && mv $T/unneeded-after $T/unneeded
exit 0
FAKE
printf '#!/bin/sh\ncat %s\n' "$T/closure" > "$T/bin/apt-cache"
printf '#!/bin/sh\n[ "$1" = --print-foreign-architectures ] && cat %s 2>/dev/null\nexit 0\n' "$T/foreign" > "$T/bin/dpkg"
printf '#!/bin/sh\ncat %s 2>/dev/null || exit 1\n' "$T/metered" > "$T/bin/busctl"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/logger"
printf '#!/bin/sh\necho "setup $*" >> %s\n[ -e %s ] && exit 1\nprintf "nvidia-driver\\t615.71.09-2\\nnvidia-driver-libs\\t615.71.09-2\\n" >> %s\nexit 0\n' "$T/setup.calls" "$T/setup.fail" "$T/installed" > "$T/bin/setup"
chmod 755 "$T"/bin/*
pci() { # ADDRESS VENDOR DEVICE CLASS
	mkdir -p "$T/sys/bus/pci/devices/$1"
	printf '0x%s\n' "$2" > "$T/sys/bus/pci/devices/$1/vendor"
	printf '0x%s\n' "$3" > "$T/sys/bus/pci/devices/$1/device"
	printf '0x%s\n' "$4" > "$T/sys/bus/pci/devices/$1/class"
}
card() { # intel | nvidia DEVICE | nvidia-audio | unreadable
	rm -rf "${T:?}/sys"
	[ "$1" = unreadable ] && return
	pci 0000:00:02.0 8086 0166 030000
	case $1 in
	nvidia) pci 0000:01:00.0 10de "$2" 030000 ;;
	nvidia-audio) pci 0000:01:00.1 10de 228e 040300 ;;
	esac
}
image() { # the image's NVIDIA packages, with some that are not NVIDIA's driver
	printf '%s\t615.71.09-2\n' nvidia-driver nvidia-driver-libs nvidia-kernel-support libnvcuvid1 nvidia-vaapi-driver libnvidia-glcore libcuda1 firmware-nvidia-gsp firmware-nvidia-graphics nvidia-detect > "$T/installed"
	printf '%s\t615.71.09-2+stereo3d9+lc1\n' nvidia-kernel-open-dkms-stereo3d sparky-stereo-nvidia-driver-lock >> "$T/installed"
	printf '%s\t1\n' sparky-stereo-cuda-repo g++ sparky-stereo-desktop >> "$T/installed"
	printf '%s\n' firmware-nvidia-gsp g++ libc6 libnvidia-glcore nvidia-driver sparky-stereo-nvidia-driver-lock | sort > "$T/closure"
	: > "$T/unneeded"; printf '%s\n' firmware-nvidia-gsp g++ libnvidia-glcore | sort > "$T/unneeded-after"
	rm -f "$T/also" "$T/purge.fail" "$T/setup.fail" "$T/metered" "$T/foreign"; : > "$T/apt.calls"; : > "$T/setup.calls"
	rm -rf "${T:?}/root"; mkdir -p "$T/root"
}
run() { PATH=$T/bin:$PATH SPARKY_STEREO_SYSFS=$T/sys SPARKY_STEREO_HARDWARE_SETUP=$T/bin/setup /usr/lib/sparky-stereo-hardware/nvidia-card "$@"; }
have() { cut -f1 "$T/installed" | sort | tr '\n' ' '; }
record() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["message"], d.get("args"))' "$1" 2>/dev/null || echo none; }
kept() { record "$T/root/var/lib/sparky-stereo-problems/sparky-stereo-hardware_nvidia-card.json"; }
told() { record "$T/root/run/sparky-stereo-problems/sparky-stereo-hardware_nvidia-card-told.json"; }
S=$T/root/var/lib/sparky-stereo-hardware

card intel; run present >/dev/null 2>&1; check "present: an Intel card only" "$?" 1
card nvidia 2504; check "present: an NVIDIA display controller" "$(run present 2>&1):$?" "0000:01:00.0 10de:2504:0"
card nvidia-audio; run present >/dev/null 2>&1; check "present: NVIDIA's HDMI audio function alone is not a card" "$?" 1
card unreadable; run present >/dev/null 2>&1; check "present: a PCI bus that cannot be read" "$?" 2

image; card intel
run auto >/dev/null 2>&1; rc=$?
check "first start, no card: exit status" "$rc" 0
check "first start, no card: NVIDIA's driver is gone, its leftovers too; nouveau's firmware, nvidia-detect and g++ stay" "$(have)" "firmware-nvidia-graphics g++ nvidia-detect sparky-stereo-desktop "
check "first start, no card: apt's plan is read before each removal" "$(grep -c -- '-s -q -o Debug::NoLocking=true purge' "$T/apt.calls")" 2
check "first start, no card: never an autoremove that removes" "$(grep ' autoremove' "$T/apt.calls" | grep -v -c -- '--simulate')" 0
check "first start, no card: the session is told, with the count" "$(told)" "LOCAL120 ['11']"
check "first start, no card: settled, no card recorded" "$([ -e "$S/nvidia-card-settled" ] && echo settled):$(cat "$S/nvidia-cards-seen")" "settled:"
: > "$T/apt.calls"; run auto >/dev/null 2>&1
check "a second start: nothing is asked of apt" "$(grep -c purge "$T/apt.calls")" 0

image; card intel; echo sparky-stereo-desktop > "$T/also"
run auto >/dev/null 2>&1; rc=$?
check "the removal would take a package that is not NVIDIA's: nothing removed, exit status 1" "$rc:$(have | wc -w)" "1:15"
check "kept by the engine, naming the package" "$(kept)" "LOCAL121 ['sparky-stereo-desktop']"
check "not settled, so the next start looks again" "$([ -e "$S/nvidia-card-settled" ] && echo settled || echo open)" open
rm -f "$T/also"; run auto >/dev/null 2>&1
check "the cause gone: removed, and the kept problem is cleared" "$(have | wc -w):$(kept)" "4:none"

image; card intel; touch "$T/purge.fail"
run auto >/dev/null 2>&1; rc=$?
check "apt fails: exit status 1, kept with the removal as its repair" "$rc:$(kept | cut -d' ' -f1)" "1:LOCAL122"

image; card nvidia 2504
run auto >/dev/null 2>&1
check "first start with a card: nothing is removed" "$(have | wc -w):$(grep -c purge "$T/apt.calls")" "15:0"
check "first start with a card: settled, the card recorded" "$(cat "$S/nvidia-cards-seen")" "10de:2504"
card intel; run auto >/dev/null 2>&1
check "the card leaves later: nothing is removed" "$(have | wc -w):$(grep -c purge "$T/apt.calls")" "15:0"

image; card unreadable
run auto >/dev/null 2>&1; rc=$?
check "a PCI bus that cannot be read: nothing decided, not settled" "$rc:$(have | wc -w):$([ -e "$S/nvidia-card-settled" ] && echo settled || echo open)" "0:15:open"

# a card that appears after the machine was settled without one
appear() { image; card intel; run auto >/dev/null 2>&1; : > "$T/setup.calls"; card nvidia 2504; }
appear; run auto >/dev/null 2>&1; rc=$?
check "a card appears: Hardware Setup's NVIDIA step runs, once" "$rc:$(cat "$T/setup.calls")" "0:setup --auto --nvidia-only"
check "a card appears: the session is told to restart" "$(told)" "LOCAL124 ['10de:2504']"
run auto >/dev/null 2>&1
check "the next start: not run again" "$(grep -c . "$T/setup.calls")" 1
appear; mkdir -p "$S"; echo nouveau > "$S/nvidia-choice"; run auto >/dev/null 2>&1
check "a card appears, nouveau was chosen in Hardware Setup: nothing is installed" "$(grep -c . "$T/setup.calls"):$(cat "$S/nvidia-cards-seen")" "0:10de:2504"
appear; echo 'u 1' > "$T/metered"; run auto >/dev/null 2>&1
check "a card appears on a metered connection: nothing downloaded, kept with its repair" "$(grep -c . "$T/setup.calls"):$(kept)" "0:LOCAL125 ['10de:2504']"
echo 'u 2' > "$T/metered"; run auto >/dev/null 2>&1
check "the connection no longer metered: installed, the kept problem cleared" "$(grep -c . "$T/setup.calls"):$(kept)" "1:none"
appear; touch "$T/setup.fail"; run auto >/dev/null 2>&1; rc=$?
check "the installation fails: exit status 1, kept with its repair" "$rc:$(kept | cut -d' ' -f1):$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repair"])' "$T/root/var/lib/sparky-stereo-problems/sparky-stereo-hardware_nvidia-card.json")" "1:LOCAL123:[['sparky-stereo-hardware', '--nvidia-card']]"

# nvidia-i386 asks for a card first
i386kept() { ls "$T/root/var/lib/sparky-stereo-problems" 2>/dev/null | grep -c nvidia-i386; }
i386() { PATH=$T/bin:$PATH SPARKY_STEREO_SYSFS=$T/sys /usr/lib/sparky-stereo-hardware/nvidia-i386 "$@"; }
image; echo i386 > "$T/foreign"; card intel
i386 check >/dev/null 2>&1
check "nvidia-i386, no card, i386 enabled, the image's driver still there: no problem is raised" "$(i386kept)" 0
card nvidia 2504
i386 check >/dev/null 2>&1
check "nvidia-i386, with a card: the missing libraries are a kept problem, as before" "$(i386kept)" 1
card intel
i386 check >/dev/null 2>&1
check "nvidia-i386, the card gone: the kept problem is cleared" "$(i386kept)" 0
out=$(i386 install 2>&1); rc=$?
check "nvidia-i386 install by hand, no card: says so and installs nothing" "$rc:$(echo "$out" | grep -c 'has no NVIDIA graphics card'):$(grep -c ' install ' "$T/apt.calls")" "0:1:0"
echo "== $( [ $fails = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ $fails = 0 ]
