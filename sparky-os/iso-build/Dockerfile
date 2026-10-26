# beta-iso-lutz build image: rootfs (mmdebstrap), packing tools, boot files from Debian, signature checks.
FROM debian:testing@sha256:9e1caa3238f2e4eee5b28c781ec712798d5d1192a6206d9e0bc7ee2861717a00
RUN sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    mmdebstrap debootstrap arch-test squashfs-tools xorriso isolinux syslinux-common syslinux-utils mtools dosfstools \
    shim-signed grub-efi-amd64-signed grub-efi-amd64-bin grub-efi-ia32-bin grub-pc-bin grub-common \
    sbsigntool pesign rsync dpkg-dev python3 python3-apt python3-pefile curl ca-certificates gnupg zstd xz-utils \
    gdisk fdisk e2fsprogs ntfs-3g file cpio kmod util-linux procps less \
 && rm -rf /var/lib/apt/lists/*
