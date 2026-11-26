#!/bin/sh
# Boot one fresh VM per case on a kernel package's own image and modules, and collect what the kernel keeps for the clone.
# Runs inside the rig container (bt129-rig), as the invoking user, no network, no device.
#
#   run-vm.sh KDIR RELEASE OUT CASE=IDENTITY [CASE=IDENTITY ...]
#
# KDIR    an unpacked linux-image package (KDIR/boot/vmlinuz-RELEASE, KDIR/lib/modules/RELEASE with modules.dep)
# OUT     results folder (one subfolder per case)
# CASE    a name; IDENTITY the BTDEV_IDENTITY for btvirt's server device (VER:MANUFACTURER:HCI_REV:LMP_SUBVER:SCO_MTU:SCO_PKTS, hex)
#         or "none" for BlueZ's own answers
# Environment: BTVIRT (the patched btvirt), BCD (bcdDevice, default 0x8891), VM_TIMEOUT (seconds, default 900)
set -eu
RIG=$(cd "$(dirname "$0")" && pwd)
KDIR=$1; REL=$2; OUT=$3; shift 3
BTVIRT=${BTVIRT:?the patched btvirt}; BCD=${BCD:-0x8891}
mkdir -p "$OUT"
I=$(mktemp -d)
mkdir -p "$I/bin" "$I/mods" "$I/proc" "$I/sys" "$I/newroot"
cp /bin/busybox "$I/bin/busybox"
n=0
modprobe -a -d "$KDIR" -S "$REL" --show-depends 9p 9pnet_virtio | while read -r kind path _; do
    [ "$kind" = insmod ] || continue
    grep -q -- "-$(basename "$path" .xz)\$" "$I/mods/order" 2>/dev/null && continue
    n=$((n+1)); name=$(printf '%02d-%s' "$n" "$(basename "$path" .xz)")
    xz -dc "$path" > "$I/mods/$name"
    echo "$name" >> "$I/mods/order"
done
cat > "$I/init" <<'EOF'
#!/bin/busybox sh
B=/bin/busybox
$B mount -t proc proc /proc
$B mount -t sysfs sysfs /sys
$B mount -t devtmpfs devtmpfs /dev
for m in $($B cat /mods/order); do $B insmod /mods/$m || echo "insmod $m failed"; done
$B mount -t 9p -o trans=virtio,version=9p2000.L,ro,msize=262144 root /newroot || exec $B sh
$B mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144 out /newroot/mnt || exec $B sh
for d in proc sys dev; do $B mount --move /$d /newroot/$d; done
rig=$($B sed -n 's/.*bt129\.rig=\([^ ]*\).*/\1/p' /newroot/proc/cmdline)
exec $B chroot /newroot /bin/sh "$rig/guest-run.sh"
EOF
chmod 755 "$I/init"
python3 -I "$RIG/mkcpio.py" "$I" "$OUT/init-$REL.cpio.gz"
rm -rf "$I"
for c in "$@"; do
    case=${c%%=*}; id=${c#*=}
    mkdir -p "$OUT/$case"
    start=$(date +%s)
    status=0
    timeout "${VM_TIMEOUT:-900}" qemu-system-x86_64 -machine pc -accel tcg -cpu max -smp 2 -m 2048 -nodefaults -no-reboot \
        -bios qboot.rom -display none -serial "file:$OUT/$case/console.log" \
        -kernel "$KDIR/boot/vmlinuz-$REL" -initrd "$OUT/init-$REL.cpio.gz" \
        -append "console=ttyS0 panic=-1 loglevel=6 bt129.kdir=$KDIR bt129.rel=$REL bt129.case=$case bt129.id=$id bt129.bcd=$BCD bt129.rig=$RIG bt129.btvirt=$BTVIRT" \
        -virtfs "local,path=/,mount_tag=root,security_model=none,readonly=on,multidevs=remap" \
        -virtfs "local,path=$OUT,mount_tag=out,security_model=none,multidevs=remap" > "$OUT/$case/qemu.log" 2>&1 || status=$?
    echo "case $case: qemu exit $status after $(( $(date +%s) - start )) s; $(cat "$OUT/$case/result.txt" 2>/dev/null || echo 'no result')"
done
