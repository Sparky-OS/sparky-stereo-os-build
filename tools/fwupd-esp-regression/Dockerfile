FROM debian:testing@sha256:fe4be93b807e7d05dccdaf54931173d9368b349f91a8170dadd787213aa3bf19
RUN DEBIAN_FRONTEND=noninteractive apt-get -y update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y install --no-install-recommends \
    gcc clang pkgconf libglib2.0-dev python3 && \
    rm -rf /var/lib/apt/lists/*
