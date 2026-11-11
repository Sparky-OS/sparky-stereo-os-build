#!/bin/sh
# docker build with the two named contexts every Dockerfile of the edition's build machinery needs for its apt steps
# (ORDER 400b; CVE-2026-109518, DSA-6607-1). The Dockerfiles' RUN lines bring the helper and the host's CA bundle in with
#   RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
#       --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
#       sh /run/https-only-apt.sh && apt-get ...
# and this wrapper names the two contexts: https-only-apt (this folder) and host-ca (the host's /etc/ssl/certs, of which only
# ca-certificates.crt is read). Without them docker build stops at the first such RUN ("failed to resolve source metadata for
# docker.io/library/host-ca"): a build that cannot get its helper never runs apt over plain HTTP.
# Use: tools/https-only-build.sh [docker build arguments]     (the same arguments as docker build)
# The block the helper writes (apt.conf.d/00sparky-block-plain-http) stays in the image, so the image refuses plain HTTP on its
# own and its apt needs /run/host-ca.crt: a container started from it that runs apt starts with the helper, like every container.
# Remove with the helper once apt 3.3.6 is in Debian testing and in the images we start from.
set -eu
here=$(dirname "$(readlink -f "$0")")
ca=${HOST_CA_DIR:-/etc/ssl/certs}
[ -r "$ca/ca-certificates.crt" ] || { echo "https-only-build: $ca/ca-certificates.crt is not readable (set HOST_CA_DIR to the folder that holds the host's ca-certificates.crt)" >&2; exit 1; }
DOCKER_BUILDKIT=1 exec docker build --build-context "https-only-apt=$here" --build-context "host-ca=$ca" "$@"
