#!/bin/sh
# Indexes our packages as a flat apt repository with its own origin, "Sparky Stereo OS",
# which the edition pins above Debian (../apt/sparky-stereo, shipped by the sparky-stereo-apt package) so updates keep the
# stereo stack. While developing it lives in /K3D/temp/sparky-os/repo, which the VM sees
# as /srv/sparky-work/repo:
#   deb [trusted=yes] file:/srv/sparky-work/repo ./
# (unsigned while developing; the published repository will be signed).
# carried/ holds unmodified Debian packages we carry for a while (not re-signed), e.g.
# libcapi20-3t64, which Wine 10 in testing needs after isdnutils left testing.
set -eu
R=${1:-/K3D/temp/sparky-os/repo}
"$(dirname "$0")/provenance.sh" "$R"/*.deb
cd "$R"
apt-ftparchive packages . >Packages
gzip -9kf Packages
apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo OS" \
	-o APT::FTPArchive::Release::Label="Sparky Stereo OS" \
	-o APT::FTPArchive::Release::Description="Sparky Stereo OS: the stereo stack and the edition's own packages" \
	release . >Release
grep -c '^Package:' Packages
