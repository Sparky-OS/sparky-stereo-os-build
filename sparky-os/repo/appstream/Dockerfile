# Debian testing (forky) for amd64 of 2026-10-20, by its image manifest digest; build-image.sh tags the image with
# the appstream-generator version pinned below, which publish-tree.sh runs by default.
FROM debian@sha256:fea1f7fbaa08297f09c45ce561d07f078dfa10acb3cb5492d9e5f42a846bfd19

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends appstream-generator=1.0.0-1 \
    && rm -rf /var/lib/apt/lists/*
