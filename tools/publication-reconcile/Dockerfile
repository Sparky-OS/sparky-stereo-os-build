ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    ulimit -c 1 && sh /run/https-only-apt.sh && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
      apt-utils bubblewrap ca-certificates gnupg lintian fakeroot locales python3-debian python3-pytest libfaketime golang-go cpio zstd systemd && \
    apt-get clean
