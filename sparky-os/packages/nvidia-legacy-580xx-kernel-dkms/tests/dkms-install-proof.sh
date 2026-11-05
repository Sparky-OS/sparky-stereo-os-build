#!/bin/bash
# The built packages, installed with apt in a clean Debian testing container with the edition's published repository
# (read-only, checked with its key, at 1001) and its 7.3 headers: DKMS builds and installs NVIDIA's 580 modules for every
# kernel named, signed with a throwaway key through DKMS's framework.conf (the way the edition's DKMS modules are signed: by
# DKMS's own key on the person's machine, sparky-os/secureboot/README.md section 4). Nothing is loaded.
# nvidia-kernel-support and nvidia-modprobe at 580 exist only in NVIDIA's repository for Debian 12, which Debian 14's APT
# refuses (its key's binding signature is SHA-1), so they are fetched here, checked against that repository's index (its
# Release verified with gpgv and NVIDIA's key), and offered to apt from a local folder, as the edition's repository will.
# Usage: dkms-install-proof.sh DEB_DIR REPO OUT KERNEL...   (IMAGE: an amd64 debian:testing image)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
DEBS=$(realpath "${1:?folder with the built .deb files}") REPO=$(realpath "${2:?the published repository of the edition}")
OUT=$(realpath -m "${3:?output folder}")
shift 3
(($#)) || { echo "name at least one kernel" >&2; exit 2; }
IMAGE=${IMAGE:?an amd64 debian:testing image}
NVREPO=https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64
NV=580.196.07-1
mkdir -p "$OUT/nvidia"
python3 - "$HERE/../cuda-debian12-archive-keyring.asc" "$OUT/nvidia/key.gpg" <<'EOF'
import base64, sys
lines = open(sys.argv[1]).read().splitlines()
body = lines[lines.index('-----BEGIN PGP PUBLIC KEY BLOCK-----') + 1:lines.index('-----END PGP PUBLIC KEY BLOCK-----')]
open(sys.argv[2], 'wb').write(base64.b64decode(''.join(l for l in body if l and not l.startswith('='))))
EOF
curl -fsS -o "$OUT/nvidia/Release" "$NVREPO/Release"
curl -fsS -o "$OUT/nvidia/Release.gpg" "$NVREPO/Release.gpg"
gpgv --keyring "$OUT/nvidia/key.gpg" "$OUT/nvidia/Release.gpg" "$OUT/nvidia/Release"
curl -fsS -o "$OUT/nvidia/Packages.gz" "$NVREPO/Packages.gz"
grep -q "^ $(sha256sum <"$OUT/nvidia/Packages.gz" | cut -d' ' -f1) .* Packages.gz$" "$OUT/nvidia/Release"
zcat "$OUT/nvidia/Packages.gz" >"$OUT/nvidia/Packages"
mkdir -p "$OUT/nvidia/debs"
for name in nvidia-kernel-support nvidia-modprobe; do
	sum=$(awk -v p="$name" -v v="$NV" '/^Package: /{pk=$2} /^Version: /{ve=$2} /^Architecture: /{ar=$2} /^SHA256: /{if (pk==p && ve==v && ar=="amd64") print $2}' "$OUT/nvidia/Packages")
	[ -n "$sum" ] || { echo "NVIDIA's index has no $name $NV" >&2; exit 1; }
	curl -fsS -o "$OUT/nvidia/debs/${name}_${NV}_amd64.deb" "$NVREPO/${name}_${NV}_amd64.deb"
	[ "$(sha256sum <"$OUT/nvidia/debs/${name}_${NV}_amd64.deb" | cut -d' ' -f1)" = "$sum" ] || { echo "$name is not NVIDIA's" >&2; exit 1; }
done
docker run --rm --platform linux/amd64 --cpus 4 -e DEBIAN_FRONTEND=noninteractive -e OWNER="$(id -u):$(id -g)" \
	-v "$REPO":/repo:ro -v "$DEBS":/debs:ro -v "$OUT/nvidia/debs":/nvidia:ro -v "$OUT":/out -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$(dirname "$(readlink -f "$0")")/../../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro "$IMAGE" bash -c '
set -euo pipefail
sh /run/https-only-apt.sh
kernels=("$@")
cat >/etc/apt/sources.list.d/sparky-stereo.sources <<S
Types: deb
URIs: file:/repo
Suites: mashtabba
Components: main
Signed-By: /repo/sparky-stereo-repo.asc
S
printf "Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n" >/etc/apt/preferences.d/00-sparky-stereo
mkdir -p /local && cp /debs/*.deb /nvidia/*.deb /local/ && rm -f /local/*-lc-hr_*.deb
apt-get update -qq && apt-get install -y -qq --no-install-recommends dpkg-dev >/dev/null
(cd /local && dpkg-scanpackages . >Packages 2>/dev/null)
echo "deb [trusted=yes] file:/local ./" >/etc/apt/sources.list.d/local.list
printf "Package: *\nPin: origin \"\"\nPin-Priority: 1001\n" >/etc/apt/preferences.d/01-local
apt-get update -qq
headers=(); for k in "${kernels[@]}"; do headers+=("linux-headers-$k"); done
apt-get install -y -qq --no-install-recommends "${headers[@]}" openssl kmod >/dev/null
mkdir -p /etc/dkms/framework.conf.d /var/lib/throwaway-key
openssl req -new -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=ORDER 354 throwaway DKMS key/" \
	-keyout /var/lib/throwaway-key/key.pem -outform DER -out /var/lib/throwaway-key/cert.der 2>/dev/null
printf "mok_signing_key=\"/var/lib/throwaway-key/key.pem\"\nmok_certificate=\"/var/lib/throwaway-key/cert.der\"\n" \
	>/etc/dkms/framework.conf.d/99-order354-throwaway.conf
# the lock first, as Hardware Setup installs it: then apt chooses NVIDIA packages under it
apt-get install -y --no-install-recommends sparky-stereo-nvidia-legacy-580xx-driver-lock >/out/install-lock.log 2>&1
apt-get install -y --no-install-recommends nvidia-legacy-580xx-kernel-dkms >/out/install-module.log 2>&1 || { tail -40 /out/install-module.log; exit 1; }
dpkg-query -W -f "\${Package} \${Version} \${db:Status-Abbrev}\n" nvidia-legacy-580xx-kernel-dkms sparky-stereo-nvidia-legacy-580xx-driver-lock nvidia-kernel-support nvidia-modprobe dkms gcc "${headers[@]}" | tee /out/installed.txt
apt-cache policy nvidia-kernel-support nvidia-driver >/out/policy.txt
status=0
for k in "${kernels[@]}"; do
	dkms install -m nvidia -v 580.196.07 -k "$k" >"/out/dkms-install-$k.log" 2>&1 || echo "$k dkms install FAILED"
	for m in nvidia nvidia-modeset nvidia-drm nvidia-uvm nvidia-peermem; do
		f=$(find "/lib/modules/$k/updates/dkms" -name "$m.ko*" | head -n1)
		if [ -z "$f" ]; then echo "$k $m MISSING"; continue; fi
		echo "$k $m signer=$(modinfo -F signer "$f") vermagic=$(modinfo -F vermagic "$f" | cut -d" " -f1)"
	done
done | tee /out/modules.txt
if grep -Eq "MISSING|FAILED" /out/modules.txt; then status=1; fi
dkms status | tee /out/dkms-status.txt
k=${kernels[0]}
f=$(find "/lib/modules/$k/updates/dkms" -name "nvidia-drm.ko*" | head -n1)
modinfo -F parm "$f" >/out/nvidia-drm-parm.txt
modinfo -F depends "$f" >/out/nvidia-drm-depends.txt
chown -R "$OWNER" /out
exit $status
' proof "$@"
echo "dkms install proof passed for: $*"
