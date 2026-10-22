# SPDX-License-Identifier: GPL-2.0-or-later
# Tool image for hibernate-bench: QEMU, swtpm, OVMF with Secure Boot, key enrolment, signing, an initramfs toolkit
# and a compiler for the test module. Nothing in it is specific to any one kernel.
FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-system-x86 ovmf swtpm swtpm-tools tpm2-tools libtss2-tcti-swtpm0 libtss2-tcti-device0 \
        python3 python3-virt-firmware sbsigntool efitools openssl \
        busybox-static cpio kmod gzip xz-utils zstd ca-certificates procps file \
        build-essential bc bison flex libssl-dev libelf-dev dwarves \
    && rm -rf /var/lib/apt/lists/*
ENV HOME=/tmp
WORKDIR /bench
