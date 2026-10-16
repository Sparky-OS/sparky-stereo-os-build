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
        xscreensaver-gl \
        xscreensaver-gl-extra \
        xvfb \
        xauth \
        python3-pil \
        python3-numpy python3-tk \
        cmake ninja-build pkg-config libx11-dev libwayland-dev libwayland-egl-backend-dev wayland-protocols libegl-dev x11-utils \
        libxmu-dev libxt-dev libxext-dev libglu1-mesa-dev \
        curl ca-certificates patch intltool libjpeg-dev libpng-dev libxft-dev libxi-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
USER 1000:1000
