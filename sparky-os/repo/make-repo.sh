#!/bin/sh
# Indexes our packages as a flat apt repository with its own origin, "Sparky Stereo",
# which the edition pins above Debian (../apt/90sparky-stereo-repo) so updates keep the
# stereo stack. While developing it lives in /K3D/temp/sparky-os/repo, which the VM sees
# as /srv/sparky-work/repo:
#   deb [trusted=yes] file:/srv/sparky-work/repo ./
# (unsigned while developing; the published repository will be signed).
set -eu
R=${1:-/K3D/temp/sparky-os/repo}
cd "$R"
apt-ftparchive packages . >Packages
gzip -9kf Packages
apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo" \
	-o APT::FTPArchive::Release::Label="Sparky Stereo" \
	-o APT::FTPArchive::Release::Description="Sparky Stereo OS: the stereo stack and the edition's own packages" \
	release . >Release
grep -c '^Package:' Packages
