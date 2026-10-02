#!/bin/bash
# NVIDIA's open kernel modules with our patches, for Sparky Stereo OS (Daniel, 2026-10-02:
# NVIDIA has not answered, so we fork and ship). The patches are the commits of our fork's
# branch stereo3d (github.com/danielcamposramos/open-gpu-kernel-modules) over 615.71.09:
#   0001 nvidia-modeset: raise default max_output_color_depth to 12   (deep colour, PR #1386)
#   0002 nvidia-drm: admit and synthesize HDMI VSDB stereo modes        (HDMI 3D, issue #1382)
#   0003 nvtiming: add the integer-rate twin of 1000/1001-rate CTA VICs
# The package is NVIDIA's own nvidia-kernel-open-dkms 615.71.09-2 with the patches applied
# to its DKMS source. It takes its own name and provides nvidia-kernel-open-dkms
# (= 615.71.09-2), because NVIDIA's nvidia-driver depends on exactly that version.
# Usage: build.sh   (the package lands in $OUT, default /K3D/temp/sparky-os/repo)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-/K3D/temp/sparky-os/repo}
UPV=615.71.09
DEBV=$UPV-2
REV=${REV:-1}
SRCDEB=${SRCDEB:-/var/cache/apt/archives/nvidia-kernel-open-dkms_${DEBV}_amd64.deb}
WORK=$(mktemp -d /K3D/temp/sparky-os/nvidia-pkg.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
if [ ! -f "$SRCDEB" ]; then
	(cd "$WORK" && apt-get download "nvidia-kernel-open-dkms=$DEBV")
	SRCDEB=$(ls "$WORK"/nvidia-kernel-open-dkms_${DEBV}_*.deb)
fi
D=$WORK/pkg
dpkg-deb -R "$SRCDEB" "$D"
for p in "$HERE"/patches/*.patch; do
	patch -s -p1 -d "$D/usr/src/nvidia-$UPV" <"$p"
	echo "applied $(basename "$p")"
done
find "$D/usr/src/nvidia-$UPV" -name '*.orig' -delete
# The control file: our name and version, providing the stock package at its version.
python3 - "$D/DEBIAN/control" "$DEBV" "$REV" <<'PY'
import sys, re
path, debv, rev = sys.argv[1], sys.argv[2], sys.argv[3]
c = open(path).read()
c = re.sub(r'^Package: .*$', 'Package: nvidia-kernel-open-dkms-stereo3d', c, flags=re.M)
c = re.sub(r'^Version: .*$', f'Version: {debv}+stereo3d{rev}', c, flags=re.M)
c = re.sub(r'^Maintainer: (.*)$', lambda m: 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nOriginal-Maintainer: ' + m.group(1), c, flags=re.M)
c = re.sub(r'^Homepage: .*$', 'Homepage: https://sparkylinux.org', c, flags=re.M)
c = re.sub(r'^Provides: (.*)$', lambda m: f'Provides: nvidia-kernel-open-dkms (= {debv}), {m.group(1)}', c, flags=re.M)
c = re.sub(r'^Replaces: (.*)$', lambda m: f'Conflicts: nvidia-kernel-open-dkms\nReplaces: nvidia-kernel-open-dkms, {m.group(1)}', c, flags=re.M)
c = re.sub(r'^Description: .*$', 'Description: NVIDIA open kernel modules (DKMS) with the stereo 3D and deep colour patches', c, flags=re.M)
c = c.rstrip('\n') + '\n Sparky Stereo OS: NVIDIA\'s nvidia-kernel-open-dkms ' + debv + ' with our patches\n (HDMI 1.4 3D modes, HDMI deep colour at the depth the sink declares by default,\n integer-rate twins of the 1000/1001-rate CTA video formats), from the branch\n stereo3d of github.com/danielcamposramos/open-gpu-kernel-modules.\n'
open(path, 'w').write(c)
PY
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print0 | sort -z | xargs -0 md5sum | sed 's| \./| |' >DEBIAN/md5sums)
deb=$OUT/nvidia-kernel-open-dkms-stereo3d_${DEBV}+stereo3d${REV}_amd64.deb
dpkg-deb --root-owner-group -Zxz -b "$D" "$deb" >/dev/null
echo "built $deb"
