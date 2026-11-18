ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    sh /run/https-only-apt.sh && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install \
      bubblewrap ca-certificates gnupg lintian fakeroot locales python3-debian systemd && \
    apt-get clean
