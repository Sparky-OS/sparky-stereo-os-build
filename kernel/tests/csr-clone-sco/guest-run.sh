#!/bin/sh
# Guest side of the CSR clone rig (row 129). Runs as PID 1 in the VM, chrooted into the rig container's root (read-only 9p),
# with the results share at /mnt. Parameters come from the kernel command line (bt129.NAME=VALUE).
set -u
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
arg() { tr ' ' '\n' < /proc/cmdline | sed -n "s/^bt129\.$1=//p"; }
KDIR=$(arg kdir); REL=$(arg rel); CASE=$(arg case); ID=$(arg id); BCD=$(arg bcd); RIG=$(arg rig); BTVIRT=$(arg btvirt)
[ "$ID" = none ] && ID=
O=/mnt/$CASE
mkdir -p "$O"
exec > "$O/guest.log" 2>&1
echo "case=$CASE release=$REL identity=${ID:-none} bcdDevice=$BCD"
mp() { modprobe -d "$KDIR" -S "$REL" "$@" || echo "modprobe $* failed"; }
# wait_for SECONDS COMMAND...: run COMMAND until it succeeds or the time is up
wait_for() { t=$(($(date +%s) + $1)); shift; until "$@"; do [ "$(date +%s)" -ge "$t" ] && return 1; sleep 0.5; done; }
stage() { echo "== $1 at $(cut -d' ' -f1 /proc/uptime) s"; dmesg > "$O/dmesg.txt"; }
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /run
for m in configfs bluetooth btusb hci_vhci libcomposite usb_f_fs; do mp "$m"; done
mp dummy_hcd is_high_speed=0
mount -t configfs none /sys/kernel/config
mount -t debugfs none /sys/kernel/debug
grep -E '^(configfs|bluetooth|btusb|hci_vhci|libcomposite|usb_f_fs|dummy_hcd) ' /proc/modules | cut -d' ' -f1 | tr '\n' ' '; echo "(loaded)"
grep -E 'configfs|functionfs' /proc/filesystems
stage modules

# btvirt in server mode only: every client of its BR/EDR socket is a device of the same emulator, so the clone (the
# gadget's controller) and the headset (headset_host.py) can connect. No hci_vhci controller: hci_vhci creates one by
# itself one second after /dev/vhci is opened, and an emulated guest on a loaded machine misses that second.
mkdir -p /tmp/bts
cp "$BTVIRT" /tmp/btvirt
BTDEV_IDENTITY="$ID" /tmp/btvirt -d -s/tmp/bts > "$O/btvirt.log" 2>&1 &
wait_for 60 test -S /tmp/bts/bt-server-bredr || echo "btvirt server socket missing"
python3 -I "$RIG/headset_host.py" /tmp/bts/bt-server-bredr /tmp/headset.addr "$O/headset.log" > /tmp/headset.out 2>&1 &
wait_for 60 test -s /tmp/headset.addr || { echo "headset host did not start"; cat /tmp/headset.out; }
stage btvirt

# the USB device: 0a12:0001 with the clone's bcdDevice, HCI through FunctionFS
G=/sys/kernel/config/usb_gadget/clone
mkdir -p $G/strings/0x409 $G/configs/c.1 $G/functions/ffs.bt
echo 0x0a12 > $G/idVendor; echo 0x0001 > $G/idProduct; echo "$BCD" > $G/bcdDevice; echo 0x0200 > $G/bcdUSB
echo 0xe0 > $G/bDeviceClass; echo 0x01 > $G/bDeviceSubClass; echo 0x01 > $G/bDeviceProtocol
echo "test clone" > $G/strings/0x409/product
ln -s $G/functions/ffs.bt $G/configs/c.1/
mkdir -p /tmp/ffs && mount -t functionfs bt /tmp/ffs
python3 -I "$RIG/ffs_clone.py" /tmp/ffs /tmp/bts/bt-server-bredr "$O/ffs.log" > /tmp/ffs.out 2>&1 &
wait_for 60 grep -q 'descriptors written' /tmp/ffs.out || { echo "ffs bridge did not start"; cat /tmp/ffs.out; }
ls /sys/class/udc | head -1 > $G/UDC
echo "bound to $(cat $G/UDC)"
wait_for 90 sh -c 'ls /sys/bus/usb/drivers/btusb/ | grep -q ":1.0"' || echo "btusb did not bind"
stage bound

C=
for h in /sys/class/bluetooth/hci*; do
    case "$(readlink -f "$h")" in */usb*) C=${h##*/};; esac
done
echo "clone=$C headset=$(cat /tmp/headset.addr)"
ps -eo pid,stat,args > "$O/ps.txt"
hciconfig "$C" up; echo "hciconfig $C up: exit $?"
stage up
hciconfig -a "$C" > "$O/hciconfig-clone.txt" 2>&1
cat /sys/kernel/debug/bluetooth/"$C"/voice_setting > "$O/voice-setting.txt" 2>&1
A_C=$(sed -n 's/.*BD Address: \([0-9A-F:]*\).*/\1/p' "$O/hciconfig-clone.txt")
A_V=$(cat /tmp/headset.addr)
python3 -I "$RIG/sco_probe.py" "$A_C" "$A_V" > "$O/sco.txt" 2>&1
sleep 2
for i in /sys/bus/usb/devices/*:1.1; do [ -e "$i/bAlternateSetting" ] && echo "$i $(cat "$i/bAlternateSetting")"; done > "$O/isoc-alt.txt"
stage done
printf 'case=%s release=%s sco=%s voice_setting=%s %s alt_requested=%s\n' "$CASE" "$REL" \
    "$(sed -n 's/.*SCO MTU: \([0-9]*:[0-9]*\).*/\1/p' "$O/hciconfig-clone.txt")" "$(cat "$O/voice-setting.txt")" \
    "$(cat "$O/sco.txt")" "$(sed -n 's/.*set USB alt:(\([0-9]*\)).*/\1/p' "$O/dmesg.txt" | tr '\n' ' ')" > "$O/result.txt"
cat "$O/result.txt"
sync
