# A real client for the server: the official MCP Python SDK, in a virtual environment, on top of the build image.
# Build it with the network, run it without: tools/https-only-build.sh -t skills-mcp-430-mcpclient:1 sparky-os/skills-mcp/envs/mcp-client
# The SDK version is pinned; the build prints its version and the SHA-256 of the files pip downloaded.
FROM skills-mcp-430-build:1
ARG MCP_VERSION=
RUN --mount=type=bind,from=https-only-apt,source=https-only-apt.sh,target=/run/https-only-apt.sh \
    --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    sh /run/https-only-apt.sh && apt-get -y update && apt-get -y --no-install-recommends install python3-venv python3-pip && apt-get clean
RUN --mount=type=bind,from=host-ca,source=ca-certificates.crt,target=/run/host-ca.crt \
    python3 -m venv /opt/mcp && SSL_CERT_FILE=/run/host-ca.crt REQUESTS_CA_BUNDLE=/run/host-ca.crt \
    /opt/mcp/bin/pip install --no-cache-dir "mcp${MCP_VERSION}" 2>&1 | tail -5 \
    && /opt/mcp/bin/pip show mcp | sed -n '1,3p' && /opt/mcp/bin/pip freeze > /opt/mcp/freeze.txt
