#!/bin/bash
# NVIDIA's 580 kernel modules for Sparky Stereo OS: the cards the edition's open modules (Turing and newer) do not run.
# NVIDIA's 580 branch is the last for Maxwell, Pascal and Volta (its 615 README lists them as "legacy_580.xx"), and the
# edition builds it so those cards get NVIDIA's driver on the edition's kernels (Daniel, 2026-11-01: "why can't we have our
# own, if nvidia's is not compatible?"; ORDER 354). Debian's own nvidia-kernel-dkms 550 does not build on Linux 7.3.
# This builds a Debian source package, nvidia-kmod-legacy-580xx: the upstream tarball is the DKMS tree of NVIDIA's own
# nvidia-kernel-dkms at the version in debian/changelog (580.196.07-1 for 580.196.07-1+sparky1), unmodified, taken from
# NVIDIA's CUDA repository for Debian 12 (the only one where NVIDIA publishes 580 for Debian); debian/ is ours. The .deb's
# SHA-256 is fixed below and checked against NVIDIA's signed index. Two binary packages come out:
# nvidia-legacy-580xx-kernel-dkms (provides nvidia-kernel-dkms at its own version, the version at which the edition carries
# NVIDIA's 580 user space, because NVIDIA's nvidia-driver depends on exactly that version) and
# sparky-stereo-nvidia-legacy-580xx-driver-lock (the APT lock generated from the same version, see its README.Debian).
# NVIDIA's 580 user space is not in this source: ../nvidia-legacy-580xx-userspace carries it at this version.
# The build goes through the Lean Code toolkit (release/build-dh-lean.sh); the tree's two precompiled objects, under the
# NVIDIA Software License, must come out byte for byte as NVIDIA ships them, and that is checked in the built package.
# To move to a new 580 version: put its .deb hash in DEB_SHA256, add a changelog entry with the new version (for example
# 580.200.01-1+sparky1) and the new /usr/src/nvidia-VERSION in debian/sparky-lean-payload-sources.json, and run this; the
# control fields and the lock follow the changelog. Update sparky-stereo-hardware's share/nvidia-legacy-580xx.ids from the
# new version's README when NVIDIA's table changes.
# Usage: build.sh [out-dir]   (default ${SPARKY_STAGING_DIR}/nvidia-kmod-legacy-580xx; REPO, default
#                              /var/tmp/sparky-repo-current; SRCDEB, a local copy of NVIDIA's .deb; SPARKY_LC_ARCHIVE_DIR,
#                              the link gate's folder, which must list NVIDIA's Debian 12 repository)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
# Last update 2026/11/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(realpath -m "${1:-${SPARKY_STAGING_DIR:?}/nvidia-kmod-legacy-580xx}")
REPO=${REPO:-/var/tmp/sparky-repo-current}
NVREPO=https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64
DEB_SHA256=ad34c436444fc50aeba6519daf923694bf762e8df4489a19849e72326b7aee37
# NVIDIA's key for that repository, the file NVIDIA's cuda-keyring 1.1-1 for Debian 12 installs
KEY_SHA256=25100d6f2eccaee7d6719a70e3c0c6145064aa9edc2c32148f693ac4c524a376
DEBV=$(dpkg-parsechangelog -l "$HERE/debian/changelog" -S Version)
NV=${DEBV%%+sparky*}
UPV=${NV%-*}
SRC=nvidia-kmod-legacy-580xx
python3 -c 'import json, sys; sys.exit(json.load(open(sys.argv[1])) != {sys.argv[2]: "."})' \
	"$HERE/debian/sparky-lean-payload-sources.json" "/usr/src/nvidia-$UPV" ||
	{ echo "debian/sparky-lean-payload-sources.json does not map /usr/src/nvidia-$UPV" >&2; exit 1; }
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/$SRC.XXXXXX")
trap 'docker run --rm -v "$WORK":/w debian:testing chown -R "$(id -u):$(id -g)" /w >/dev/null 2>&1; rm -rf "$WORK"' EXIT
# NVIDIA's key for its Debian 12 repository, armored next to this script, is NVIDIA's file byte for byte once dearmored
# (RFC 9580 section 6: base64 between the header and the CRC line). gpgv checks the Release signature with it here; Debian 14's
# APT (sqv) refuses this key, whose binding signature is SHA-1, so no package of this source names that repository.
python3 - "$HERE/cuda-debian12-archive-keyring.asc" "$WORK/nvidia-debian12.gpg" <<'EOF'
import base64, sys
lines = open(sys.argv[1]).read().splitlines()
body = lines[lines.index('-----BEGIN PGP PUBLIC KEY BLOCK-----') + 1:lines.index('-----END PGP PUBLIC KEY BLOCK-----')]
open(sys.argv[2], 'wb').write(base64.b64decode(''.join(l for l in body if l and not l.startswith('='))))
EOF
[ "$(sha256sum <"$WORK/nvidia-debian12.gpg" | cut -d' ' -f1)" = "$KEY_SHA256" ] ||
	{ echo "cuda-debian12-archive-keyring.asc is not NVIDIA's Debian 12 key" >&2; exit 1; }
# NVIDIA's .deb: its hash is the one NVIDIA's index lists, the index's hash is in the Release file, and the Release file is
# signed with that key.
curl -fsS -o "$WORK/Release" "$NVREPO/Release"
curl -fsS -o "$WORK/Release.gpg" "$NVREPO/Release.gpg"
gpgv --keyring "$WORK/nvidia-debian12.gpg" "$WORK/Release.gpg" "$WORK/Release"
curl -fsS -o "$WORK/Packages.gz" "$NVREPO/Packages.gz"
grep -q "^ $(sha256sum <"$WORK/Packages.gz" | cut -d' ' -f1) .* Packages.gz$" "$WORK/Release" ||
	{ echo "NVIDIA's Packages.gz does not match its signed Release" >&2; exit 1; }
zcat "$WORK/Packages.gz" >"$WORK/Packages"
grep -qx "SHA256: $DEB_SHA256" "$WORK/Packages" ||
	{ echo "NVIDIA's signed index does not list nvidia-kernel-dkms $NV with SHA-256 $DEB_SHA256" >&2; exit 1; }
SRCDEB=${SRCDEB:-}
if [ -z "$SRCDEB" ]; then
	curl -fsS -o "$WORK/nvidia-kernel-dkms_${NV}_amd64.deb" "$NVREPO/nvidia-kernel-dkms_${NV}_amd64.deb"
	SRCDEB=$WORK/nvidia-kernel-dkms_${NV}_amd64.deb
fi
[ "$(sha256sum <"$SRCDEB" | cut -d' ' -f1)" = "$DEB_SHA256" ] || { echo "$SRCDEB is not NVIDIA's nvidia-kernel-dkms $NV" >&2; exit 1; }
[ "$(dpkg-deb -f "$SRCDEB" Package Version | tr '\n' ' ')" = "Package: nvidia-kernel-dkms Version: $NV " ] ||
	{ echo "$SRCDEB is not nvidia-kernel-dkms $NV" >&2; exit 1; }
dpkg-deb -x "$SRCDEB" "$WORK/x"
mv "$WORK/x/usr/src/nvidia-$UPV" "$WORK/$SRC-$UPV"
(cd "$WORK/$SRC-$UPV" && sha256sum nvidia/nv-kernel.o_binary nvidia-modeset/nv-modeset-kernel.o_binary) >"$WORK/blobs.sha256"
tar --sort=name --owner=0 --group=0 --numeric-owner --format=gnu -C "$WORK" -cf - "$SRC-$UPV" |
	xz -T4 -6 >"$WORK/${SRC}_$UPV.orig.tar.xz"
rm -rf "$WORK/x"
cp -a "$HERE/debian" "$WORK/$SRC-$UPV/"
bash "$HERE/../../release/build-dh-lean.sh" "$WORK" "$SRC-$UPV" "$DEBV+lc1" "$REPO"
# The NVIDIA Software License, 1.1(d): its binary files are distributed only unmodified.
deb=$(ls "$WORK"/out/nvidia-legacy-580xx-kernel-dkms_*+lc1_amd64.deb)
mkdir "$WORK/check"
dpkg-deb -x "$deb" "$WORK/check"
(cd "$WORK/check/usr/src/nvidia-$UPV" && sha256sum -c --quiet "$WORK/blobs.sha256") ||
	{ echo "$deb changed NVIDIA's precompiled objects" >&2; exit 1; }
echo "NVIDIA's precompiled objects are byte for byte NVIDIA's in $(basename "$deb")"
mkdir -p "$OUT"
cp -a "$WORK"/out/. "$OUT"/
sync
echo "built: $(cd "$OUT" && ls)"
