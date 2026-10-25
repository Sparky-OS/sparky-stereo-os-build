#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Tests of lib/secureboot.py on fake EFI system partitions: where the certificate goes, and the GRUB entry it writes
# in each of the nine languages. Needs python3 only.
#   secureboot-tests.sh PATH/TO/sparky-stereo-boot
set -u
P=$(cd "${1:?package source}" && pwd)
CERT=$P/../../secureboot/sparky-stereo-secureboot-2026.der
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }
run() { SPARKY_STEREO_ESP=$T/$1 SPARKY_STEREO_CERT=$CERT SPARKY_STEREO_LANG_DIR=$P/lang SPARKY_STEREO_OS_RELEASE=$T/os-release \
	LANG=$2 python3 -I "$P/lib/secureboot.py" "$3"; }
printf 'ID=sparky\n' > "$T/os-release"

# an installed system as Calamares leaves it: shim in EFI/sparky and EFI/debian, and shim as EFI/BOOT/BOOTX64.EFI
mkdir -p "$T/a/EFI/sparky" "$T/a/EFI/debian" "$T/a/EFI/boot" "$T/a/EFI/Microsoft/Boot"
for d in sparky debian; do echo shim > "$T/a/EFI/$d/shimx64.efi"; echo mm > "$T/a/EFI/$d/mmx64.efi"; done
echo shim > "$T/a/EFI/boot/BOOTX64.EFI"; echo windows > "$T/a/EFI/Microsoft/Boot/bootmgfw.efi"
run a en_US.UTF-8 esp >/dev/null
check "certificate beside shim in EFI/sparky" "$(cmp -s "$CERT" "$T/a/EFI/sparky/sparky-stereo-secureboot-2026.der" && echo same)" same
check "certificate beside shim in EFI/debian" "$(cmp -s "$CERT" "$T/a/EFI/debian/sparky-stereo-secureboot-2026.der" && echo same)" same
check "certificate on the removable-media path (BOOTX64.EFI is shim)" "$(cmp -s "$CERT" "$T/a/EFI/boot/sparky-stereo-secureboot-2026.der" && echo same)" same
check "nothing in Windows' folder" "$(ls "$T/a/EFI/Microsoft/Boot")" bootmgfw.efi
check "a second run writes nothing" "$(run a en_US.UTF-8 esp)" ""

# BOOTX64.EFI that is not shim (another system's loader) gets no certificate
mkdir -p "$T/b/EFI/sparky" "$T/b/EFI/BOOT"; echo shim > "$T/b/EFI/sparky/shimx64.efi"; echo other > "$T/b/EFI/BOOT/BOOTX64.EFI"
run b en_US.UTF-8 esp >/dev/null
check "no certificate beside another loader's BOOTX64.EFI" "$(ls "$T/b/EFI/BOOT")" BOOTX64.EFI

# no shim at all (a BIOS boot, or another boot loader): no entry
mkdir -p "$T/c/EFI/other"; echo grub > "$T/c/EFI/other/grubx64.efi"
check "no shim: no GRUB entry" "$(run c en_US.UTF-8 grub)" ""

# the entry: title in the system's language, the steps in nine languages (the system's first), MokManager beside GRUB,
# and the fallback only under Secure Boot
for l in en_US pl_PL pt_BR fr_FR de_DE ja_JP ko_KR zh_CN zh_TW; do
	out=$(run a $l.UTF-8 grub)
	code=$l; case $l in pt_BR|zh_CN|zh_TW) ;; *) code=${l%_*} ;; esac
	title=$(sed -n 's/^LOCAL12="\(.*\)"$/\1/p' "$P/lang/$code")
	name=$(sed -n 's/^LOCAL14="\(.*\)"$/\1/p' "$P/lang/$code")
	check "$l: title" "$(echo "$out" | sed -n "s/^ *menuentry '\(.*\)' --id sparky-enroll {$/\1/p")" "$title"
	check "$l: its language first" "$(echo "$out" | grep -m1 'echo "' | sed 's/^ *echo "\([^:]*\):.*/\1/')" "$name"
	check "$l: nine languages" "$(echo "$out" | grep -c -E 'echo "(English|Polski|Português|Français|Deutsch|日本語|한국어|简体中文|繁體中文):')" 9
	check "$l: the system's folder named" "$(echo "$out" | grep -c 'sparky-stereo-secureboot-2026.der')" 9
done
out=$(run a de_DE.UTF-8 grub)
check "MokManager from GRUB's own folder" "$(echo "$out" | grep -c 'chainloader "$cmdpath/mmx64.efi"')" 1
check "fallback only when shim_lock is set" "$(echo "$out" | grep -A1 'if \[ "$shim_lock" = y \]; then' | tail -1 | tr -d ' ')" "setfallback=sparky-enroll"
check "only on 64-bit UEFI" "$(echo "$out" | head -2 | tr -d ' ' | tr '\n' ' ')" 'if["$grub_platform"=efi];then if["$grub_cpu"=x86_64];then '
check "no character GRUB would expand in the texts" "$(echo "$out" | grep 'echo "' | grep -c -E '\$|\\')" 0
w=$(echo "$out" | grep 'echo "' | sed 's/^ *echo "//; s/"$//' | python3 -c 'import sys,unicodedata; print(max(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l.rstrip("\n")) for l in sys.stdin))')
check "lines fit 98 columns (800x600)" "$([ "$w" -le 98 ] && echo yes)" yes
echo "== $( [ $fails = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ $fails = 0 ]
