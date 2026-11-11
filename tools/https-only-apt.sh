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
# Not root: see the unprivileged branch below (HTTPS_ONLY_APT_CONF).
# Use: docker run ... -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro \
#        -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro IMAGE sh -c 'sh /run/https-only-apt.sh && ...'
set -eu
[ -r /run/host-ca.crt ] || { echo "https-only-apt: /run/host-ca.crt is not mounted (mount the host's /etc/ssl/certs/ca-certificates.crt there, read-only)" >&2; exit 1; }
conf='// CVE-2026-109518: plain-HTTP sources refused until apt 3.3.6 reaches Debian testing (ORDER 400)
Acquire::http::Proxy "http://plain-http-blocked-cve-2026-109518.invalid/";
Acquire::https::Proxy "DIRECT";
Acquire::https::CaInfo "/run/host-ca.crt";'
if [ "$(id -u)" != 0 ]; then
	# Unprivileged container (UID 1000 with apt folders of its own, gl-stereo's packaging scripts, ORDER 400b): /etc/apt is
	# not writable, so the same three settings go to the file named by HTTPS_ONLY_APT_CONF and the caller points apt at it:
	#   HTTPS_ONLY_APT_CONF=/path/https-only-apt.conf sh /run/https-only-apt.sh && export APT_CONFIG=/path/https-only-apt.conf
	# Its sources are the caller's own and must be written as https:// (the check in tests/https-only-apt refuses http://).
	[ -n "${HTTPS_ONLY_APT_CONF:-}" ] || { echo "https-only-apt: not root, so /etc/apt cannot be changed; set HTTPS_ONLY_APT_CONF to a writable file and export APT_CONFIG=that file afterwards" >&2; exit 1; }
	printf '%s\n' "$conf" > "$HTTPS_ONLY_APT_CONF"
	echo "https-only-apt: settings written to $HTTPS_ONLY_APT_CONF (export APT_CONFIG=$HTTPS_ONLY_APT_CONF), plain http refused"
	exit 0
fi
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
	[ -f "$f" ] || continue
	sed -i 's|http://|https://|g' "$f"
done
printf '%s\n' "$conf" > /etc/apt/apt.conf.d/00sparky-block-plain-http
echo "https-only-apt: sources on https, plain http refused"
