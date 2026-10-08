#!/bin/sh
# Signs the kernel image inside a linux-image .deb with a distribution's Secure Boot key, checks the
# signature, and writes the signed package, in a throwaway container (nothing installed on the host).
# Run it in the build pipeline, before the package is published: the version stays the same.
# Usage: sign-kernel-deb.sh <private key folder> <linux-image.deb in> <signed .deb out>
set -eu
[ $# -eq 3 ] || { echo "usage: $0 <private key folder> <linux-image.deb in> <signed .deb out>" >&2; exit 2; }
KEYDIR=$(cd "$1" && pwd); IN=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); OUTD=$(cd "$(dirname "$3")" && pwd); OUTF=$(basename "$3")
HERE=$(cd "$(dirname "$0")" && pwd)
docker image inspect secureboot-tools >/dev/null 2>&1 || docker build -q -t secureboot-tools -f "$HERE/Dockerfile.sbtools" "$HERE" >/dev/null
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
	-v "$KEYDIR:/key:ro" -v "$IN:/in/kernel.deb:ro" -v "$OUTD:/out" secureboot-tools sh -c '
	set -e; w=$(mktemp -d); dpkg-deb -R /in/kernel.deb "$w/pkg"
	for v in "$w"/pkg/boot/vmlinuz-*; do
		sbsign --key /key/key.pem --cert /key/cert.pem --output "$v.signed" "$v" && mv "$v.signed" "$v"
		sbverify --cert /key/cert.pem "$v"
	done
	(cd "$w/pkg" && find . -path ./DEBIAN -prune -o -type f -print | sed "s|^\./||" | sort | tr "\n" "\0" | xargs -0 -r md5sum > DEBIAN/md5sums)
	dpkg-deb --root-owner-group -Zxz -b "$w/pkg" "/out/'"$OUTF"'" >/dev/null'
