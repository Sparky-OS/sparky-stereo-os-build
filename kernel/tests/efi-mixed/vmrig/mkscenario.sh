#!/bin/bash
# mkscenario.sh OUT ROOTFS_TAR FIRST_KERNEL_RELEASE DEB... : an installed Debian forky system on 32-bit UEFI, as two
# disk images (run as root in the rig image; the images end owned by OWNER_UID).
# Both go into OUT/disk.img, one GPT disk (partition 1 the ESP, 2 the root):
#   root          ext4 (label rigroot): the rootfs, the DEBs installed with dpkg (kernels: Debian's linux-base scripts
#                 and initramfs-tools make /boot), /etc/default/grub for a serial console and init=/rig-init
#   ESP           FAT: Debian's GRUB 2.14 for i386-efi as EFI/BOOT/BOOTIA32.EFI; it runs /boot/grub/grub.cfg of the
#                 root disk when update-grub has made one, else starts FIRST_KERNEL with nokaslr once (phase A)
# /rig-init prints the probe facts; in phase A (/rig-update present) it first runs update-grub on the booted system
# (so 31-sparky-stereo-ia32.cfg sees fw_platform_size 32) and prints every linux line of the new grub.cfg.
set -euo pipefail
OUT=$1 TAR=$2 FIRSTK=$3; shift 3
mkdir -p "$OUT"; chown "${OWNER_UID:-0}:${OWNER_UID:-0}" "$OUT"; R=$(mktemp -d)
tar --zstd -xpf "$TAR" -C "$R"
mkdir -p "$R/tmp/debs"; cp "$@" "$R/tmp/debs/"
for d in "$@"; do
	b=$(basename "$d")
	case "$b" in linux-image-*) chroot "$R" dpkg -i "/tmp/debs/$b" ;; esac
done
for d in "$@"; do
	b=$(basename "$d")
	case "$b" in linux-image-*) ;; *) chroot "$R" dpkg -i "/tmp/debs/$b" ;; esac
done
rm -rf "$R/tmp/debs"
# IA32_NOKASLR=auto|yes|no sets the boot package's option in the installed system
if [ -n "${IA32_NOKASLR:-}" ]; then
	sed -i '/^SPARKY_STEREO_IA32_NOKASLR=/d' "$R/etc/default/sparky-stereo-boot"
	echo "SPARKY_STEREO_IA32_NOKASLR=$IA32_NOKASLR" >> "$R/etc/default/sparky-stereo-boot"
fi
printf 'virtio_pci\nvirtio_blk\next4\n' >> "$R/etc/initramfs-tools/modules"
for k in "$R"/boot/vmlinuz-*; do chroot "$R" update-initramfs -u -k "${k##*/vmlinuz-}" >/dev/null 2>&1 || true; done
cat > "$R/etc/default/grub" <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=Rig
GRUB_CMDLINE_LINUX_DEFAULT=""
GRUB_CMDLINE_LINUX="console=ttyS0,115200 init=/rig-init panic=0"
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200"
GRUB_DISABLE_OS_PROBER=true
EOF
cat > "$R/rig-init" <<'EOF'
#!/bin/sh
mount -t proc proc /proc; mount -t sysfs sys /sys; mount -t devtmpfs dev /dev 2>/dev/null
echo "EFI246 uname=$(uname -r)"
echo "EFI246 fw_platform_size=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)"
echo "EFI246 cmdline=$(cat /proc/cmdline)"
grep -i -E "Kernel (code|rodata)" /proc/iomem | sed 's/^ */EFI246 iomem /'
if [ -e /rig-update ]; then
	mount -o remount,rw /
	update-grub 2>&1 | sed 's/^/EFI246 update-grub: /'
	grep -E '^\s*linux\s' /boot/grub/grub.cfg | sed 's/^\s*/EFI246 grubline: /'
	rm -f /rig-update; sync; mount -o remount,ro /
fi
[ -d /sys/firmware/efi/efivars ] && echo "EFI246 runtime=yes"
echo "EFI246 efidir $(ls /sys/firmware/efi | tr '\n' ' ')"
echo EFI246-OK
sync; /bin/busybox poweroff -f
EOF
chmod 755 "$R/rig-init"; touch "$R/rig-update"; mkdir -p "$R/boot/grub"
rm -f "$OUT/root.img"; truncate -s 2400M "$OUT/root.img"
mkfs.ext4 -q -L rigroot -d "$R" "$OUT/root.img"
rm -rf "$R"
T=$(mktemp -d)
cat > "$T/grub.cfg" <<EOF
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
set timeout=0
insmod part_gpt
insmod part_msdos
insmod ext2
insmod fat
search --no-floppy --label --set=root rigroot
if [ -f /boot/grub/grub.cfg ]; then configfile /boot/grub/grub.cfg; fi
echo "EFI246 phase A: first boot of $FIRSTK"
linux /boot/vmlinuz-$FIRSTK root=LABEL=rigroot ro console=ttyS0,115200 init=/rig-init panic=0 nokaslr
initrd /boot/initrd.img-$FIRSTK
boot
EOF
grub-mkstandalone -O i386-efi --locales= --fonts= --themes= -o "$T/BOOTIA32.EFI" "boot/grub/grub.cfg=$T/grub.cfg"
rm -f "$OUT/esp.img"; truncate -s 48M "$OUT/esp.img"; mkfs.vfat -F 32 -n RIGESP "$OUT/esp.img" >/dev/null
mmd -i "$OUT/esp.img" ::/EFI ::/EFI/BOOT; mcopy -i "$OUT/esp.img" "$T/BOOTIA32.EFI" ::/EFI/BOOT/BOOTIA32.EFI
rm -rf "$T"
# one GPT disk (OVMF connects only the boot disk): partition 1 the ESP, partition 2 the root
rm -f "$OUT/disk.img"; truncate -s 2500M "$OUT/disk.img"
printf 'label: gpt\nstart=2048, size=98304, type=uefi, name=esp\nstart=100352, size=4915200, type=linux, name=root\n' | sfdisk -q "$OUT/disk.img"
dd if="$OUT/esp.img" of="$OUT/disk.img" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$OUT/root.img" of="$OUT/disk.img" bs=1M seek=49 conv=notrunc,sparse status=none
rm -f "$OUT/esp.img" "$OUT/root.img"
chown "${OWNER_UID:-0}:${OWNER_UID:-0}" "$OUT"/disk.img
ls -la "$OUT"
