#!/bin/sh
# Signs the out-of-tree kernel modules of a module tree (DKMS's updates/dkms, extra) with a distribution's
# Secure Boot key, in a throwaway container, so nothing is installed on the host: a signature already there
# (DKMS signs with its own key, /var/lib/dkms/mok.key, made where it built) is removed, the module is signed
# with sign-file from the kernel's own headers package, and the signer is checked with modinfo.
# A live ISO carries modules built at packing time; under Secure Boot our kernel loads only modules signed
# with a key it trusts, so they are signed with the edition's key, whose certificate the person enrols.
# Usage: sign-modules.sh <private key folder> <linux-headers.deb> <tree in> <signed tree out>
#   <tree in> holds lib/modules/<release>/...; only *.ko and *.ko.xz files outside kernel/ are signed.
set -eu
[ $# -eq 4 ] || { echo "usage: $0 <private key folder> <linux-headers.deb> <tree in> <signed tree out>" >&2; exit 2; }
KEYDIR=$(cd "$1" && pwd); HDR=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); IN=$(cd "$3" && pwd)
mkdir -p "$4"; OUT=$(cd "$4" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
docker image inspect secureboot-modules-tools >/dev/null 2>&1 || docker build -q --platform linux/amd64 -t secureboot-modules-tools -f "$HERE/Dockerfile.sbmodules" "$HERE" >/dev/null
docker run --rm --platform linux/amd64 --user "$(id -u):$(id -g)" \
	-v "$KEYDIR:/key:ro" -v "$HDR:/in/headers.deb:ro" -v "$IN:/in/tree:ro" -v "$OUT:/out" secureboot-modules-tools sh -c '
	set -e; w=$(mktemp -d); dpkg-deb -x /in/headers.deb "$w/h"
	sf=$(find "$w/h/usr/src" -path "*/scripts/sign-file" -type f | head -n1)
	[ -x "$sf" ] || { echo "no sign-file in the headers package" >&2; exit 1; }
	cp -a /in/tree/. /out/
	find /out/lib/modules -path "*/kernel" -prune -o \( -name "*.ko" -o -name "*.ko.xz" \) -print | while read -r m; do
		k=${m%.xz}; [ "$k" = "$m" ] || xz -d -f "$m"
		python3 - "$k" <<PY
import struct, sys
p = sys.argv[1]; d = open(p, "rb").read()
marker = b"~Module signature appended~\\n"
if d.endswith(marker):
    sig_len = struct.unpack(">I", d[-len(marker) - 4:-len(marker)])[0]
    d = d[:len(d) - len(marker) - 12 - sig_len]
    open(p, "wb").write(d)
PY
		"$sf" sha256 /key/key.pem /key/cert.der "$k"
		[ "$k" = "$m" ] || xz -f --check=crc32 "$k"
		echo "$m: $(modinfo -F signer "$m")"
	done'
