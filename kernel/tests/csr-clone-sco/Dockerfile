# Rig for kernel/tests/csr-clone-sco (row 129): KUnit under QEMU, a guest that boots the edition's kernel packages, and BlueZ's emulator built from Debian's source.
# Pin the base: --build-arg BASE=debian:testing@sha256:... --platform linux/amd64 (row 129 used the amd64 image
# sha256:56d1e9668480ade19248f38679308ec3d091b186dd177c696469575bfdb1d5bb, Debian testing of 2026-11-23).
ARG BASE=debian:testing
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/debian.sources && \
    sh /run/https-only-apt.sh && apt-get update -qq && apt-get -y install --no-install-recommends \
      build-essential bc bison flex libelf-dev libssl-dev python3 qemu-system-x86 cpio kmod git ca-certificates \
      xz-utils zstd rsync busybox-static bluez dpkg-dev pkgconf \
      libglib2.0-dev libdbus-1-dev libudev-dev libical-dev libreadline-dev \
    && apt-get source --download-only bluez && mkdir -p /opt/src && mv bluez_* /opt/src/ \
    && apt-cache policy bluez busybox-static qemu-system-x86 gcc > /opt/src/apt-policy.txt \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /work && chmod 1777 /work
ENV HOME=/work
WORKDIR /work
