#!/bin/sh
# Signs a kernel image (vmlinuz, an EFI stub) with a distribution's Secure Boot key and checks the
# signature, in a throwaway container with sbsigntool, so nothing is installed on the host.
# Usage: sign-kernel.sh <private key folder> <vmlinuz in> <vmlinuz out>
set -eu
[ $# -eq 3 ] || { echo "usage: $0 <private key folder> <vmlinuz in> <vmlinuz out>" >&2; exit 2; }
KEYDIR=$(cd "$1" && pwd); IN=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); OUTD=$(cd "$(dirname "$3")" && pwd); OUTF=$(basename "$3")
HERE=$(cd "$(dirname "$0")" && pwd)
docker image inspect secureboot-tools >/dev/null 2>&1 || docker build -q -t secureboot-tools -f "$HERE/Dockerfile.sbtools" "$HERE" >/dev/null
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
	-v "$KEYDIR:/key:ro" -v "$IN:/in/vmlinuz:ro" -v "$OUTD:/out" secureboot-tools sh -c "
	sbsign --key /key/key.pem --cert /key/cert.pem --output /out/$OUTF /in/vmlinuz &&
	sbverify --cert /key/cert.pem /out/$OUTF"
