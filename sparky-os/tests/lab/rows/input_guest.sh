#!/bin/bash
# input_guest.sh SIDE: in the lab22-guest image. Builds the lab's small guest for the kernel of SIDE (ours: the edition's
# 7.3.4-stereo3d18 with its SDL3 package; stock: Debian's 7.3.4+deb14 with Debian's SDL3), boots it in QEMU (KVM, no network,
# no display), where a virtual HID joystick with 128 buttons, 8 axes and 4 hats is made through UHID, and judges the answer.
# Mounts: /lab/guest (rig/guest), /lab/rows, /kern (the unpacked kernel packages), /sdl (ours: the unpacked libsdl3-0).
set -euE
trap 'echo "lab setup error at line $LINENO" >&2; exit 2' ERR
SIDE=$1
W=/tmp/lab-guest
rm -rf $W; mkdir -p $W/bins $W/g
gcc -O2 -static -o $W/bins/hidtest /lab/rig/guest/hidtest.c
gcc -O2 -o $W/bins/sdltest /lab/rig/guest/sdltest.c $(pkg-config --cflags --libs sdl3)
SDL=""
[ "$SIDE" = ours ] && SDL="--sdl-lib $(ls /sdl/usr/lib/x86_64-linux-gnu/libSDL3.so.0.*)"
python3 -I /lab/rig/guest/mkguest.py /kern/$SIDE/x $W/g --modules hid,hid_generic,uhid,evdev --bins $W/bins --init /lab/rig/guest/init-input $SDL \
  > /evidence/mkguest.log 2>&1 || { echo "SKIP: the guest could not be assembled: $(tail -1 /evidence/mkguest.log)"; exit 77; }
timeout 150 qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 2 -m 1G -no-reboot -nodefaults \
  -kernel $W/g/vmlinuz -initrd $W/g/initrd.gz -append "console=ttyS0 panic=-1 loglevel=3" -display none -vga none -serial stdio \
  > /evidence/console.log 2> /evidence/qemu.log || true
exec python3 -I /lab/rows/input_judge.py /evidence/console.log
