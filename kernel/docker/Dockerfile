# Build image of kernel/build-deb.sh: debian:testing with the tools a kernel build with Rust, BTF and Debian packaging needs
# (gcc 16, rustc, rust-src, bindgen, pahole >= 1.22, debhelper). Built once; build-deb.sh then runs every build as the
# invoking user (docker run --user), so nothing is installed at build time and no file in the output is owned by root.
FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive LC_ALL=C
RUN apt-get update -qq && apt-get -y install --no-install-recommends \
      build-essential bc bison flex libssl-dev libelf-dev libdw-dev dwarves cpio kmod rsync \
      python3 git ca-certificates xz-utils zstd patch \
      debhelper dpkg-dev fakeroot lsb-release \
      rustc rust-src bindgen libclang-dev \
      && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /work && chmod 1777 /work
ENV HOME=/work
WORKDIR /work
