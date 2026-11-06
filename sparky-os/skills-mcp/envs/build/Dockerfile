# The image the skills packages are built and checked in: Debian testing for amd64, the edition's own cgm-zig package
# (never a station path), and the packaging and Lean Code prerequisites. Build it with the network, run it without.
#   tools/https-only-build.sh --build-context cgmpool=<folder with the cgm-zig .deb> -t skills-mcp-430-build:1 sparky-os/skills-mcp/envs/build
# FROM names a local amd64 Debian testing image; pull one by its digest first and tag it as below.
FROM skills-mcp-430-base:1
ENV DEBIAN_FRONTEND=noninteractive \
    DEBFULLNAME="Daniel Ramos (Capitain Jack)" \
    DEBEMAIL="Capitain_Jack@yahoo.com"
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    --mount=type=bind,from=cgmpool,target=/cgmpool \
    sh /run/https-only-apt.sh && test "$(dpkg --print-architecture)" = amd64 \
    && apt-get -y update \
    && apt-get -y --no-install-recommends install \
       bubblewrap ca-certificates binutils dpkg-dev file gcc git node-acorn nodejs perl python3 python3-yaml xz-utils \
       /cgmpool/cgm-zig_0.16.0+cgm.0399d2b19b-2+lc1_amd64.deb \
    && apt-get clean
