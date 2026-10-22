#!/bin/bash
# NVIDIA's open kernel modules with our patches, for Sparky Stereo OS (Daniel, 2026-10-02:
# NVIDIA has not answered, so we fork and ship). debian/patches holds the commits of our fork's
# branch stereo3d (github.com/danielcamposramos/open-gpu-kernel-modules) over the NVIDIA version:
#   0001 nvidia-modeset: raise default max_output_color_depth to 12   (deep colour, PR #1386)
#   0002 nvidia-drm: admit and synthesize HDMI VSDB stereo modes        (HDMI 3D, issue #1382)
#   0003 nvtiming: add the integer-rate twin of 1000/1001-rate CTA VICs
#   0004 nvidia-modeset: HDMI Deep Colour at 16 bits per component (DC_48); the default
#        max_output_color_depth becomes 16, so the sink's declared depth decides
#   0005 nvidia-drm: conftests for the generic connector colour properties (kernel 7.3 API)
#   0006 nvidia-drm, nvidia-modeset: scan out HDMI 3D frame packing and side by side (full)
#   0007 nvidia-drm: send the HDMI 3D InfoFrame (VSIF) built from the mode, so the TV
#        switches itself into 3D when KWin sets a 3D mode
#   0008 nvidia-drm: "max bpc", "Broadcast RGB" and "color format" connector properties
# Since +stereo3d4 this builds a Debian source package, nvidia-kmod-open: the upstream tarball
# is the DKMS tree of NVIDIA's own nvidia-kernel-open-dkms at the version in debian/changelog
# (615.71.09-2 for 615.71.09-2+stereo3d4), debian/ is ours. Two binary packages come out:
# nvidia-kernel-open-dkms-stereo3d (provides nvidia-kernel-open-dkms at NVIDIA's exact version,
# because NVIDIA's nvidia-driver depends on exactly that version) and sparky-stereo-nvidia-driver-lock
# (the APT lock generated from the same version, see debian/sparky-stereo-nvidia-driver-lock.README.Debian).
# To move to a new NVIDIA version: rebase the patches, add a changelog entry with the new version
# (for example 620.10.01-1+stereo3d1), run this; the control fields and the lock follow the changelog.
# Usage: build.sh   (OUT, default ${SPARKY_STAGING_DIR}/nvidia-kmod-open;
#                    SRCDEB, default: apt-get download of NVIDIA's package, signature checked by apt)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_STAGING_DIR:?}/nvidia-kmod-open}
DEBV=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
NV=${DEBV%%+stereo3d*}
UPV=${NV%-*}
WORK=$(mktemp -d ${SPARKY_SCRATCH:?}/sparky-os/nvidia-kmod-open.XXXXXX)
trap 'docker run --rm -v "$WORK":/w debian:testing chown -R "$(id -u):$(id -g)" /w >/dev/null 2>&1; rm -rf "$WORK"' EXIT
SRCDEB=${SRCDEB:-}
if [ -z "$SRCDEB" ]; then
	(cd "$WORK" && apt-get download "nvidia-kernel-open-dkms=$NV")
	SRCDEB=$(ls "$WORK"/nvidia-kernel-open-dkms_"$NV"_*.deb)
fi
dpkg-deb -x "$SRCDEB" "$WORK/x"
mv "$WORK/x/usr/src/nvidia-$UPV" "$WORK/nvidia-kmod-open-$UPV"
tar --sort=name --owner=0 --group=0 --numeric-owner --format=gnu -C "$WORK" -cf - "nvidia-kmod-open-$UPV" |
	xz -T4 -6 >"$WORK/nvidia-kmod-open_$UPV.orig.tar.xz"
cp -a "$HERE/debian" "$WORK/nvidia-kmod-open-$UPV/"
docker run --rm -v "$WORK":/w debian:testing bash -c "export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq && apt-get install -y -qq --no-install-recommends build-essential debhelper dh-dkms >/dev/null
	cd /w/nvidia-kmod-open-$UPV && dpkg-buildpackage -us -uc"
mkdir -p "$OUT"
cp "$WORK"/*.deb "$WORK"/*.dsc "$WORK"/*.debian.tar.xz "$WORK"/*.orig.tar.xz "$WORK"/*.buildinfo "$WORK"/*.changes "$OUT"/
sync
echo "built $(cd "$OUT" && ls *.deb *.dsc)"
