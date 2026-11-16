#!/bin/bash
# Builds the toy repositories of the variants test inside a container (needs dpkg-deb and apt-ftparchive) into $1:
#   complete/   amd64 and amd64v3 indexes, the amd64v3 one a full copy (what the edition's repository must publish)
#   incomplete/ the same, but the amd64v3 index lists only what has a v3 build (the trap apt 3.3.3 showed: it supplants the baseline index)
# sstoy has a baseline build and an amd64v3 build (Architecture-Variant: amd64v3); sbonly has a baseline build only.
set -euo pipefail
OUT=${1:?output folder}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkpkg() { # name version variant text
	local d=$W/$1-$3
	mkdir -p "$d/DEBIAN" "$d/usr/bin"
	{
		printf 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: test\nDescription: toy %s\n' "$1" "$2" "$1"
		[ "$3" = base ] || printf 'Architecture-Variant: %s\n' "$3"
	} >"$d/DEBIAN/control"
	printf '#!/bin/sh\necho "%s"\n' "$4" >"$d/usr/bin/$1"
	chmod 755 "$d/usr/bin/$1"
	mkdir -p "$OUT/pool/$3"
	dpkg-deb --root-owner-group -b "$d" "$OUT/pool/$3/$1_$2_amd64.deb" >/dev/null
}
mkdir -p "$OUT"
mkpkg sstoy 1.0 base "sstoy built for baseline"
mkpkg sstoy 1.0 amd64v3 "sstoy built for x86-64-v3"
mkpkg sbonly 1.0 base "sbonly built for baseline"
for kind in complete incomplete; do
	R=$OUT/$kind
	mkdir -p "$R/dists/toy/main/binary-amd64" "$R/dists/toy/main/binary-amd64v3" "$R/pool"
	rm -rf "$R/pool"; mkdir -p "$R/pool"
	cp -r "$OUT/pool/." "$R/pool/"
	(cd "$R" && apt-ftparchive --arch amd64 packages pool/base >dists/toy/main/binary-amd64/Packages
	 if [ $kind = complete ]; then
		{ apt-ftparchive --arch amd64 packages pool/amd64v3; apt-ftparchive --arch amd64 packages pool/base | awk -v RS= -v ORS='\n\n' '/Package: sbonly/'; } >dists/toy/main/binary-amd64v3/Packages
	 else
		apt-ftparchive --arch amd64 packages pool/amd64v3 >dists/toy/main/binary-amd64v3/Packages
	 fi
	 {
		printf 'Origin: toy\nLabel: toy\nSuite: toy\nCodename: toy\nArchitectures: amd64 amd64v3\nComponents: main\nDate: Mon, 16 Nov 2026 00:00:00 UTC\n'
		printf 'SHA256:\n'
		for f in main/binary-amd64/Packages main/binary-amd64v3/Packages; do
			printf ' %s %s %s\n' "$(sha256sum dists/toy/$f | cut -d' ' -f1)" "$(stat -c %s dists/toy/$f)" "$f"
		done
	 } >dists/toy/Release)
done
