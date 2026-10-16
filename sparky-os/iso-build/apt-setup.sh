#!/bin/sh
# Writes the beta's apt sources, keys and pins into a root directory (default /).
# Sources: Debian testing (all four components), SparkyLinux (core, tiamat), deb-multimedia (forky),
# the edition's development repository (mounted at /repo, flat, trusted), NVIDIA's CUDA repository
# for the 615 userspace the edition's open modules are built for.
# Keys are checked against their published fingerprints or checksums before use.
# Usage: apt-setup.sh [root]
set -eu
R=${1:-}
SPARKY_FPR=2517567C137975AC92300A385CA76B26C40956B8
CUDA_KEY_SHA256=d0d4ef986a44400f9db33c600ef33a985175e7cc63d805a10e1839c7a1e78f5f
W=$(mktemp -d)
mkdir -p "$R/etc/apt/sources.list.d" "$R/etc/apt/preferences.d" "$R/etc/apt/keyrings" "$R/etc/apt/trusted.gpg.d"

curl -fsSL https://repo.sparkylinux.org/sparky-repo.asc -o "$W/sparky.asc"
got=$(gpg --show-keys --with-colons "$W/sparky.asc" | awk -F: '$1=="fpr"{print $10; exit}')
[ "$got" = "$SPARKY_FPR" ] || { echo "apt-setup: SparkyLinux key fingerprint $got, expected $SPARKY_FPR" >&2; exit 1; }
install -m644 "$W/sparky.asc" "$R/etc/apt/trusted.gpg.d/sparky-repo.asc"

dpkg-deb --fsys-tarfile /repo/carried/deb-multimedia-keyring_2024.9.1_all.deb | tar -xO ./usr/share/keyrings/deb-multimedia-keyring.pgp > "$R/etc/apt/keyrings/deb-multimedia-keyring.pgp"

curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb -o "$W/cuda-keyring.deb"
printf '%s  %s\n' "$CUDA_KEY_SHA256" "$W/cuda-keyring.deb" | sha256sum -c - >/dev/null
dpkg-deb --fsys-tarfile "$W/cuda-keyring.deb" | tar -xO ./usr/share/keyrings/cuda-archive-keyring.gpg > "$R/etc/apt/keyrings/sparky-stereo-cuda.gpg"

cat > "$R/etc/apt/sources.list.d/debian.sources" <<'EOF'
Types: deb
URIs: http://deb.debian.org/debian
Suites: testing
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
cat > "$R/etc/apt/sources.list.d/sparky.sources" <<'EOF'
Types: deb
URIs: https://repo.sparkylinux.org/
Suites: core tiamat
Components: main
Signed-By: /etc/apt/trusted.gpg.d/sparky-repo.asc
EOF
cat > "$R/etc/apt/sources.list.d/sparky-stereo-deb-multimedia.sources" <<'EOF'
Types: deb
URIs: https://www.deb-multimedia.org
Suites: forky
Components: main non-free
Signed-By: /etc/apt/keyrings/deb-multimedia-keyring.pgp
EOF
cat > "$R/etc/apt/sources.list.d/sparky-stereo-build.sources" <<'EOF'
Types: deb
URIs: file:/repo
Suites: ./
Trusted: yes
EOF
cat > "$R/etc/apt/sources.list.d/sparky-stereo-cuda.sources" <<'EOF'
Types: deb
URIs: https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/
Suites: /
Architectures: amd64
Signed-By: /etc/apt/keyrings/sparky-stereo-cuda.gpg
EOF
cat > "$R/etc/apt/preferences.d/sparky" <<'EOF'
Package: *
Pin: release o=SparkyLinux
Pin-Priority: 1001
EOF
cp /edition-apt/sparky-stereo /edition-apt/sparky-stereo-only-ours "$R/etc/apt/preferences.d/"
cat > "$R/etc/apt/preferences.d/91sparky-stereo-cuda" <<'EOF'
Package: *
Pin: origin developer.download.nvidia.com
Pin-Priority: 1002
EOF
rm -rf "$W"
