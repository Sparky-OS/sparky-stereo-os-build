# The image the supply-chain tools run in (ORDER 394, 394b): Python, dpkg-dev and a virtual environment whose packages
# are installed by hash.
# Build:  tools/https-only-build.sh --build-arg BASE=IMAGE -t NAME .   (IMAGE: an amd64 debian:testing pulled by digest)
# git is not needed (the tools read files) and jsonschema was never imported, so neither is installed.
ARG BASE
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    sh /run/https-only-apt.sh && apt-get update -qq && apt-get -y --no-install-recommends install python3 python3-venv dpkg-dev xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/v && /opt/v/bin/pip install --require-hashes --no-deps -r /tmp/requirements.txt \
    && /opt/v/bin/pip freeze > /opt/v/freeze.txt && rm /tmp/requirements.txt
