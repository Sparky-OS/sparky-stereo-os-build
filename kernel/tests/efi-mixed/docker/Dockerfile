FROM sparky-lc-kernel-checks-qemu:20261020
RUN DEBIAN_FRONTEND=noninteractive apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    grub-efi-ia32-bin grub-efi-amd64-bin grub-pc-bin grub-common mtools dosfstools xorriso e2fsprogs fdisk && rm -rf /var/lib/apt/lists/*
