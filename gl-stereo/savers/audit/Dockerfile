FROM --platform=linux/amd64 gl-stereo-package-proof:3
USER root
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    sh /run/https-only-apt.sh && printf 'deb https://deb.debian.org/debian testing main\n' > /etc/apt/audit.list \
 && apt-get -o Dir::Etc::sourcelist=/etc/apt/audit.list -o Dir::Etc::sourceparts=- update \
 && DEBIAN_FRONTEND=noninteractive apt-get -y --no-upgrade install apitrace \
 && apt-get clean
USER 1000:1000
