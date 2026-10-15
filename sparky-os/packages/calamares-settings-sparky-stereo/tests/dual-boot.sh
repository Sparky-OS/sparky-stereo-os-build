#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/15
# Tests lib/dual-boot with os-prober's output for a Windows disk, a Linux one and none.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
probe() { printf '#!/bin/sh\nprintf "%s"\n' "$1" > "$T/os-prober"; chmod 755 "$T/os-prober"; }
run() { ADJTIME=$T/$1/adjtime GRUBD=$T/$1/grub.d OS_PROBER=$T/os-prober "$HERE/lib/dual-boot"; }
mkdir -p $T/w $T/l $T/n
probe '/dev/vda1@/EFI/Microsoft/Boot/bootmgfw.efi:Windows Boot Manager:Windows:efi\n'; run w
check "Windows beside: local time" "$(sed -n 3p $T/w/adjtime 2>/dev/null)" LOCAL
check "Windows beside: os-prober on" "$(grep -v '^#' $T/w/grub.d/sparky-stereo-dual-boot.cfg 2>/dev/null)" GRUB_DISABLE_OS_PROBER=false
probe '/dev/vda3:Debian GNU/Linux forky/sid:Debian:linux\n'; run l
check "Linux beside: clock unchanged" "$(cat $T/l/adjtime 2>/dev/null || echo none)" none
check "Linux beside: os-prober as Debian has it" "$(ls $T/l/grub.d 2>/dev/null || echo none)" none
probe ''; run n
check "nothing beside: unchanged" "$(ls $T/n)" ""
echo "dual-boot: $pass passed, $fail failed"
[ "$fail" = 0 ]
