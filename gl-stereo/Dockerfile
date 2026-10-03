# SPDX-License-Identifier: GPL-2.0-or-later OR MIT
FROM debian:testing
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get -y install --no-install-recommends \
        build-essential \
        libgl1-mesa-dev \
        libegl1-mesa-dev \
        libglx-mesa0 \
        mesa-utils \
        xscreensaver \
        xscreensaver-data \
        xscreensaver-data-extra \
        xscreensaver-gl \
        xscreensaver-gl-extra \
        xvfb \
        xauth \
        python3-pil \
        python3-numpy python3-tk paraview python3-paraview \
        cmake ninja-build pkg-config libx11-dev libwayland-dev wayland-protocols libegl-dev x11-utils \
        gdb \
        file \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
