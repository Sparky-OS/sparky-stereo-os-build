#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/15
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/15
# Tests lib/dual-boot-clock with os-prober's output for a Windows disk, a Linux one and none.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
probe() { printf '#!/bin/sh\nprintf "%s"\n' "$1" > "$T/os-prober"; chmod 755 "$T/os-prober"; }
probe '/dev/vda1@/EFI/Microsoft/Boot/bootmgfw.efi:Windows Boot Manager:Windows:efi\n'
ADJTIME=$T/a1 OS_PROBER=$T/os-prober "$HERE/lib/dual-boot-clock"
check "Windows beside: local time" "$(sed -n 3p $T/a1 2>/dev/null)" LOCAL
probe '/dev/vda3:Debian GNU/Linux forky/sid:Debian:linux\n'
ADJTIME=$T/a2 OS_PROBER=$T/os-prober "$HERE/lib/dual-boot-clock"
check "Linux beside: unchanged" "$(cat $T/a2 2>/dev/null || echo none)" none
probe ''
ADJTIME=$T/a3 OS_PROBER=$T/os-prober "$HERE/lib/dual-boot-clock"
check "nothing beside: unchanged" "$(cat $T/a3 2>/dev/null || echo none)" none
echo "dual-boot-clock: $pass passed, $fail failed"
[ "$fail" = 0 ]
