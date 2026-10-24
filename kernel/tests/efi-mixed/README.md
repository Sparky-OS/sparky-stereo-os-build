# EFI mixed mode boot rig (32-bit UEFI, 64-bit kernel)

Boots a kernel many times in QEMU under 32-bit OVMF and the other firmware, headless, and records for each boot whether it reached userspace with EFI runtime services, the physical address of `_text` and of `__efi64_thunk_ret_tramp`, and at a fault the oops and the page-table entry.
It is the proof of series group 35 (ORDER 246): unfixed kernels fault in about half of the KASLR boots through GRUB on 32-bit UEFI, every time with the trampoline above 4 GiB; fixed kernels pass every boot.

Everything runs in containers (`--device /dev/kvm`); nothing touches a display.

```
W=/var/tmp/my-work; R=$PWD/kernel/tests/efi-mixed
docker build -t efi-mixed-rig $R/docker                        # QEMU, OVMF x64, GRUB 2.14 for i386-efi and x86_64-efi, e2fsprogs, sfdisk
python3 -I $R/fetch-ovmf32.py $W/fw                            # Debian trixie's ovmf-ia32 (forky has none), checksum checked, unpacked
RUN="docker run --rm --cpus 4 --memory 16g --user $(id -u):$(id -g) --device /dev/kvm --group-add $(getent group kvm | cut -d: -f3) -v $W:$W -v $W/fw:/fw:ro -v $R:/rig:ro efi-mixed-rig"
$RUN /rig/mkinitrd.sh $W/initrd-probe.img                       # busybox probe: prints the facts, powers off
$RUN /rig/matrix.sh $W TAG /boot/vmlinuz-X /boot/System.map-X   # 100 boots via GRUB ia32, 20 each: ia32 stub, x64 GRUB, x64 stub, SeaBIOS
```

`matrix.sh` prints one line per case from `summary.py`: the results and, for each boot whose address is known, whether the trampoline was above 4 GiB and whether a fault's RIP is the trampoline's 32-bit return address truncated (label 2, offset 9).
`boots.py` alone boots one kernel N times with one firmware and loader (`--loader grub` with a disk from `mkgrubdisk.sh`, or `--loader direct` for QEMU `-kernel`).

## The installed system (sparky-stereo-boot's nokaslr rule)

`vmrig/` makes a Debian forky system on one GPT disk (ESP with GRUB i386-efi, ext4 root), installs the given kernel packages and sparky-stereo-boot, boots it once on 32-bit OVMF to run update-grub there (so `31-sparky-stereo-ia32.cfg` sees `fw_platform_size` 32), prints every linux line it wrote, then boots its menu N times.

```
docker run --name rootfs debian:forky bash -c 'apt-get update && apt-get -y install --no-install-recommends linux-base initramfs-tools kmod grub-common grub2-common grub-efi-ia32-bin python3 systemd libdrm2 udev e2fsprogs busybox zstd'
mkdir -p $W/vmrig && docker export rootfs | zstd -o $W/vmrig/rootfs-base.tar.zst && docker rm rootfs
W=$W R=$R $R/vmrig/run-scenario.sh NAME 30 7.3.0-rc6-stereo3d12 System.map linux-image-7.3.0-rc6-stereo3d12_*.deb sparky-stereo-boot_*.deb
IA32_NOKASLR=no W=$W R=$R $R/vmrig/run-scenario.sh ...          # the package option set in the installed system
```

Measured on 2026-10-24 (QEMU 11.1.2, KVM, q35, 4 GiB, Debian's ovmf-ia32 2025.02-8+deb13u1, GRUB 2.14-4): build 11 faulted in 24 of 50 KASLR boots through GRUB ia32, upstream master in 33 of 50, build 12 in none of 100 per flavour.
