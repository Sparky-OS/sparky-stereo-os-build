# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
FROM debian@sha256:c57e2b343e3a8bd7e59f1c063fe34355f209d0fd8afa291ed96f65a8c1f08cb1
ENV DEBIAN_FRONTEND=noninteractive \
    DEBFULLNAME="Daniel Ramos (Capitain Jack)" \
    DEBEMAIL="Capitain_Jack@yahoo.com"
RUN test "$(dpkg --print-architecture)" = amd64 \
    && apt-get -y update \
    && apt-get -y --no-install-recommends install \
       build-essential ca-certificates cmake debhelper dpkg-dev git \
       clang-21 libclang-21-dev libclang-cpp21-dev liblld-21-dev \
       libxml2-dev libzstd-dev lld-21 llvm-21-dev ninja-build \
       pkgconf python3 xz-utils zlib1g-dev \
    && apt-get clean
