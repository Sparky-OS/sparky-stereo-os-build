#!/bin/sh
# Writes the image build's apt sources, keys and pins into a root directory (default /).
# Sources: Debian testing (all four components), SparkyLinux (core, tiamat), deb-multimedia (forky),
# the edition's repository, NVIDIA's CUDA repository for the 615 userspace the edition's open modules
# are built for.
# The edition's repository (EDITION_REPO): live (default), the published repository at
# https://repo.sparkyos.org/ exactly as people get it, written as sparky-stereo-apt writes it; or flat,
# the development repository mounted at /repo (flat, trusted), the beta lanes' way.
# Keys are checked against their published fingerprints or checksums before use.
# Usage: apt-setup.sh [root]   (live needs root /: it runs apt there)
set -eu
R=${1:-}
EDITION_REPO=${EDITION_REPO:-live}
SPARKY_FPR=2517567C137975AC92300A385CA76B26C40956B8
EDITION_URI=https://repo.sparkyos.org/
EDITION_FPR=10DFD38DAD1E4808BC688E5A945E5D079A2A0B9C
CUDA_KEY_SHA256=d0d4ef986a44400f9db33c600ef33a985175e7cc63d805a10e1839c7a1e78f5f
W=$(mktemp -d)
mkdir -p "$R/etc/apt/sources.list.d" "$R/etc/apt/preferences.d" "$R/etc/apt/keyrings" "$R/etc/apt/trusted.gpg.d"

curl -fsSL https://repo.sparkylinux.org/sparky-repo.asc -o "$W/sparky.asc"
got=$(gpg --show-keys --with-colons "$W/sparky.asc" | awk -F: '$1=="fpr"{print $10; exit}')
[ "$got" = "$SPARKY_FPR" ] || { echo "apt-setup: SparkyLinux key fingerprint $got, expected $SPARKY_FPR" >&2; exit 1; }
install -m644 "$W/sparky.asc" "$R/etc/apt/trusted.gpg.d/sparky-repo.asc"

case "$EDITION_REPO" in
live)
	[ -z "$R" ] || [ "$R" = / ] || { echo "apt-setup: EDITION_REPO=live writes into / only" >&2; exit 1; }
	curl -fsSL "${EDITION_URI}sparky-stereo-repo.asc" -o "$W/edition.asc"
	got=$(gpg --show-keys --with-colons "$W/edition.asc" | awk -F: '$1=="fpr"{print $10; exit}')
	[ "$got" = "$EDITION_FPR" ] || { echo "apt-setup: edition key fingerprint $got, expected $EDITION_FPR" >&2; exit 1; }
	# the key and the source where sparky-stereo-keyring and sparky-stereo-apt put them (pack.sh lets the packages own them)
	install -m644 "$W/edition.asc" "$R/etc/apt/trusted.gpg.d/sparky-stereo-repo.asc"
	cat > "$R/etc/apt/sources.list.d/sparky-stereo.sources" <<EOF
Types: deb deb-src
URIs: $EDITION_URI
Suites: mashtabba
Components: main
Signed-By: /etc/apt/trusted.gpg.d/sparky-stereo-repo.asc
EOF
	# deb-multimedia's keyring as the edition's repository carries it, checked by that repository's signed index
	apt-get update -qq
	(cd "$W" && apt-get download -qq deb-multimedia-keyring)
	dpkg-deb --fsys-tarfile "$W"/deb-multimedia-keyring_*.deb | tar -xO ./usr/share/keyrings/deb-multimedia-keyring.pgp > "$R/etc/apt/keyrings/deb-multimedia-keyring.pgp"
	;;
flat)
	dpkg-deb --fsys-tarfile /repo/carried/deb-multimedia-keyring_2024.9.1_all.deb | tar -xO ./usr/share/keyrings/deb-multimedia-keyring.pgp > "$R/etc/apt/keyrings/deb-multimedia-keyring.pgp"
	;;
*) echo "apt-setup: EDITION_REPO must be live or flat" >&2; exit 1 ;;
esac

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
if [ "$EDITION_REPO" = flat ]; then
	cat > "$R/etc/apt/sources.list.d/sparky-stereo-build.sources" <<'EOF'
Types: deb
URIs: file:/repo
Suites: ./
Trusted: yes
EOF
fi
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
