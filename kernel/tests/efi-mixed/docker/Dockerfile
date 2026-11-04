FROM sparky-lc-kernel-checks-qemu:20261020
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    sh /run/https-only-apt.sh && DEBIAN_FRONTEND=noninteractive apt-get -y update && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    grub-efi-ia32-bin grub-efi-amd64-bin grub-pc-bin grub-common mtools dosfstools xorriso e2fsprogs fdisk && rm -rf /var/lib/apt/lists/*
