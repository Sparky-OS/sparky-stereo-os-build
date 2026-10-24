#!/bin/busybox sh
/bin/busybox --install -s /bin
mkdir -p /proc /sys /dev
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev 2>/dev/null
echo "EFI246 uname=$(uname -r)"
echo "EFI246 fw_platform_size=$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)"
echo "EFI246 cmdline=$(cat /proc/cmdline)"
grep -i -E "Kernel (code|rodata|data|bss)" /proc/iomem | sed 's/^ */EFI246 iomem /'
dmesg | grep -i -E "efi: (EFI v|Runtime|mixed)|NX|kaslr|efi_mixed|runtime services" | sed 's/^/EFI246 dmesg /'
if [ -r /sys/firmware/efi/runtime ] || [ -d /sys/firmware/efi/efivars ]; then echo "EFI246 runtime=yes"; fi
ls /sys/firmware/efi/ 2>/dev/null | tr '\n' ' ' | sed 's/^/EFI246 efidir /'; echo
echo EFI246-OK
sleep 1
poweroff -f
