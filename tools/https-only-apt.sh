#!/bin/sh
# Run first in every container that uses apt, until apt 3.3.6 (the fix for CVE-2026-109518, DSA-6607-1) is in Debian
# testing and in the images we start from (Opus, 2026-11-04, ORDER 400; Daniel: "change them to https", "then block
# http sources for now"). The flaw lets an attacker on the network path swap a verified package during apt's retries
# of a plain-HTTP download.
# What it does inside the container:
#   - every http:// URI in apt's sources becomes https:// (deb.debian.org, security, deb-multimedia and the others
#     all serve HTTPS);
#   - apt trusts the host's CA bundle, mounted read-only at /run/host-ca.crt, so HTTPS works before the image has
#     ca-certificates (the bundle is mounted beside, never over /etc/ssl/certs, so ca-certificates still installs);
#   - any plain http:// source left is refused by name: "Could not resolve plain-http-blocked-cve-2026-109518.invalid".
# Use: docker run ... -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
#        -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro IMAGE sh -c 'sh /run/https-only-apt.sh && ...'
set -eu
[ -r /run/host-ca.crt ] || { echo "https-only-apt: /run/host-ca.crt is not mounted (mount the host's /etc/ssl/certs/ca-certificates.crt there, read-only)" >&2; exit 1; }
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
	[ -f "$f" ] || continue
	sed -i 's|http://|https://|g' "$f"
done
cat > /etc/apt/apt.conf.d/00sparky-block-plain-http <<'EOF'
// CVE-2026-109518: plain-HTTP sources refused until apt 3.3.6 reaches Debian testing (ORDER 400)
Acquire::http::Proxy "http://plain-http-blocked-cve-2026-109518.invalid/";
Acquire::https::Proxy "DIRECT";
Acquire::https::CaInfo "/run/host-ca.crt";
EOF
echo "https-only-apt: sources on https, plain http refused"
