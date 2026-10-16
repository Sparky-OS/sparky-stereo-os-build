#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# Tests lib/efi-fallback on EFI partitions laid out as the installer leaves them: beside Windows,
# beside another Linux, alone, alone over a stale bare GRUB, on a BIOS machine, and without shim.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
probe() { printf '#!/bin/sh\nprintf "%s"\n' "$1" > "$T/os-prober"; chmod 755 "$T/os-prober"; }
esp() { # a partition with our chain in EFI/sparky (lower case, as the installer makes it)
	mkdir -p "$T/$1/EFI/sparky" "$T/fw"
	for f in shimx64.efi grubx64.efi mmx64.efi fbx64.efi grub.cfg; do echo "$f of the system" > "$T/$1/EFI/sparky/$f"; done
}
run() { ESP=$T/$1 OS_PROBER=$T/os-prober EFI_FIRMWARE=${2:-$T/fw} TARGET=${TARGET:-} "$HERE/lib/efi-fallback" >/dev/null; }
same() { cmp -s "$1" "$2" && echo same || echo different; }

esp w; mkdir -p $T/w/EFI/Microsoft/Boot $T/w/EFI/Boot
echo "Windows' boot manager" > $T/w/EFI/Microsoft/Boot/bootmgfw.efi; echo "Windows' fallback" > $T/w/EFI/Boot/bootx64.efi
probe '/dev/vda1@/EFI/Microsoft/Boot/bootmgfw.efi:Windows Boot Manager:Windows:efi\n'; run w
check "Windows: its fallback stays" "$(cat $T/w/EFI/Boot/bootx64.efi)" "Windows' fallback"
check "Windows: nothing added" "$(ls $T/w/EFI/Boot)" "bootx64.efi"

esp w2; mkdir -p $T/w2/EFI/Microsoft/Boot; echo "Windows' boot manager" > $T/w2/EFI/Microsoft/Boot/bootmgfw.efi
probe ''; run w2
check "Windows not probed, its boot manager there: no fallback written" "$(ls $T/w2/EFI)" "Microsoft
sparky"

esp l; mkdir -p $T/l/EFI/BOOT; echo "another Linux's fallback" > $T/l/EFI/BOOT/BOOTX64.EFI
probe '/dev/vda3:Debian GNU/Linux forky/sid:Debian:linux\n'; run l
check "another Linux with a fallback: it stays" "$(cat $T/l/EFI/BOOT/BOOTX64.EFI)" "another Linux's fallback"

esp l2; probe '/dev/vda3:Debian GNU/Linux forky/sid:Debian:linux\n'; run l2
check "another Linux, no fallback yet: shim written" "$(same $T/l2/EFI/BOOT/BOOTX64.EFI $T/l2/EFI/sparky/shimx64.efi)" same

esp a; probe ''; run a
check "alone: shim as BOOTX64.EFI" "$(same $T/a/EFI/BOOT/BOOTX64.EFI $T/a/EFI/sparky/shimx64.efi)" same
check "alone: GRUB beside it" "$(same $T/a/EFI/BOOT/grubx64.efi $T/a/EFI/sparky/grubx64.efi)" same
check "alone: MokManager beside it" "$(same $T/a/EFI/BOOT/mmx64.efi $T/a/EFI/sparky/mmx64.efi)" same
check "alone: GRUB's configuration beside it" "$(same $T/a/EFI/BOOT/grub.cfg $T/a/EFI/sparky/grub.cfg)" same
check "alone: the four files, no fallback.efi" "$(ls $T/a/EFI/BOOT | tr '\n' ' ')" "BOOTX64.EFI grub.cfg grubx64.efi mmx64.efi "

esp s; mkdir -p $T/s/EFI/Boot; echo "bare GRUB" > $T/s/EFI/Boot/bootx64.efi; echo "old grub" > $T/s/EFI/Boot/grubx64.efi
probe ''; run s
check "alone over a bare GRUB: one BOOTX64, now shim" "$(ls $T/s/EFI/Boot | grep -ci bootx64.efi)" 1
check "alone over a bare GRUB: shim" "$(same $T/s/EFI/Boot/BOOTX64.EFI $T/s/EFI/sparky/shimx64.efi)" same
check "alone over a bare GRUB: GRUB replaced" "$(same $T/s/EFI/Boot/grubx64.efi $T/s/EFI/sparky/grubx64.efi)" same

esp t; mkdir -p $T/t/EFI/BOOT; echo "an old bare GRUB" > $T/t/EFI/BOOT/BOOTX64.EFI
probe '/dev/vda2:Sparky Stereo OS 9 (Mashtabba):Sparky:linux\n'; TARGET=/dev/vda2 run t
check "os-prober lists only the new system itself: shim written" "$(same $T/t/EFI/BOOT/BOOTX64.EFI $T/t/EFI/sparky/shimx64.efi)" same

esp b; probe ''; run b $T/no-efi-firmware
check "BIOS machine: nothing written" "$(ls $T/b/EFI)" sparky

mkdir -p $T/n/EFI/sparky; echo grub > $T/n/EFI/sparky/grubx64.efi; probe ''; run n
check "no shim in EFI/sparky: nothing written" "$(ls $T/n/EFI)" sparky

echo "efi-fallback: $pass passed, $fail failed"
[ "$fail" = 0 ]
