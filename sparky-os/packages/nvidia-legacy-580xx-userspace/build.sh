#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# NVIDIA's 580 user space for Sparky Stereo OS, for the Maxwell, Pascal and Volta cards the edition's open modules
# (Turing and newer) do not run (ORDER 354). NVIDIA's 580 branch is the last for these cards, and NVIDIA publishes it for
# Debian only in its CUDA repository for Debian 12, whose key Debian 14's APT refuses (a SHA-1 binding signature;
# its repository for Debian 13 starts at 590, Debian's own packaging stops at 555). So the edition carries NVIDIA's own
# Debian 12 packages (Daniel, 2026-11-01: "why can't we have our own, if nvidia's is not compatible? why aren't we shipping
# the full functionality?"), amd64 and the i386 libraries Steam, Wine and 32-bit games need, as versioned edition packages:
#   - NVIDIA's files and maintainer scripts byte for byte (the NVIDIA Software License distributes the binary files only
#     unmodified, 1.1(d)(i) and 2.3, and asks that a modified file carry a prominent notice of the change, 2.5); Lean Code
#     keeps each of them as NVIDIA ships it (lean.release build-tree --preserve-plan) and its manifest says why;
#   - the control file the edition's, at the version of the edition's 580 kernel module (nvidia-legacy-580xx-kernel-dkms's
#     debian/changelog plus Lean Code's +lc1), with NVIDIA's exact relations among the carried packages at it;
#   - three files of the edition: README.sparky-stereo, changelog.Debian.ARCH.gz (Debian's name for a binary-only entry,
#     so NVIDIA's own changelog stays) and the Lean Code manifest.
# packages.tsv names what is carried, with the SHA-256 NVIDIA's signed index gave on 2026-11-02 (carry.py select wrote
# it); excluded.tsv names, with its reason, every other package of the index at that version. The build checks NVIDIA's
# signature on the Release file with gpgv and NVIDIA's key (the one armored beside the module's recipe), the index against
# the Release file, the lists against the index, each .deb against its recorded hash, and each built package against
# NVIDIA's (carry.py verify); it stops on any difference.
# To move to a new 580 version: rebuild the module at it first (its changelog gives this build's version), then run
# carry.py select on NVIDIA's new index, review excluded.tsv against it, write this folder's changelog entry and run this.
# Needs python3, dpkg-dev, gpgv and curl (the edition's sparky-lc-migration image has them).
# Usage: build.sh [out-dir]   (default ${SPARKY_STAGING_DIR}/nvidia-legacy-580xx-userspace; NVDEBS, a folder that already
#                              holds NVIDIA's files, each checked against its recorded hash; SPARKY_SCRATCH, the work folder)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
# Last update 2026/11/03
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLKIT=$(cd "$HERE/../.." && pwd)
MODULE=$HERE/../nvidia-legacy-580xx-kernel-dkms
OUT=$(realpath -m "${1:-${SPARKY_STAGING_DIR:?}/nvidia-legacy-580xx-userspace}")
NVREPO=https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64
# NVIDIA's key for that repository, the file NVIDIA's cuda-keyring 1.1-1 for Debian 12 installs
KEY_SHA256=25100d6f2eccaee7d6719a70e3c0c6145064aa9edc2c32148f693ac4c524a376
# NVIDIA's copyright file (the NVIDIA Software License), the same in every amd64 package of the set; the packages NVIDIA
# ships without one (its i386 packages, cuda-drivers) get it, byte for byte (carry.py stage)
COPYRIGHT_SHA256=9a9f6ab4e21ac09ea5a6fbb8a721ae0192220959471fba5d9daeb07a60022253
MODV=$(dpkg-parsechangelog -l "$MODULE/debian/changelog" -S Version)
VERSION=$MODV+lc1
NV=${MODV%%+sparky*}
[ "$(head -n1 "$HERE/changelog" | sed -n 's/^@SOURCE@ (\([^)]*\)) .*binary-only=yes$/\1/p')" = "$VERSION" ] ||
	{ echo "the first entry of $HERE/changelog is not for $VERSION, the module's version with +lc1" >&2; exit 1; }
[ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ] && { echo "$OUT is not empty; never replace a built version" >&2; exit 1; }
WORK=$(mktemp -d "${SPARKY_SCRATCH:?}/nvidia-legacy-580xx-userspace.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# NVIDIA's key, armored beside the module's recipe, is NVIDIA's file byte for byte once dearmored (RFC 9580 section 6)
python3 -I - "$MODULE/cuda-debian12-archive-keyring.asc" "$WORK/nvidia-debian12.gpg" <<'EOF'
import base64, sys
lines = open(sys.argv[1]).read().splitlines()
body = lines[lines.index('-----BEGIN PGP PUBLIC KEY BLOCK-----') + 1:lines.index('-----END PGP PUBLIC KEY BLOCK-----')]
open(sys.argv[2], 'wb').write(base64.b64decode(''.join(l for l in body if l and not l.startswith('='))))
EOF
[ "$(sha256sum <"$WORK/nvidia-debian12.gpg" | cut -d' ' -f1)" = "$KEY_SHA256" ] ||
	{ echo "cuda-debian12-archive-keyring.asc is not NVIDIA's Debian 12 key" >&2; exit 1; }
curl -fsS -o "$WORK/Release" "$NVREPO/Release"
curl -fsS -o "$WORK/Release.gpg" "$NVREPO/Release.gpg"
gpgv --keyring "$WORK/nvidia-debian12.gpg" "$WORK/Release.gpg" "$WORK/Release"
curl -fsS -o "$WORK/Packages.gz" "$NVREPO/Packages.gz"
grep -q "^ $(sha256sum <"$WORK/Packages.gz" | cut -d' ' -f1) .* Packages.gz$" "$WORK/Release" ||
	{ echo "NVIDIA's Packages.gz does not match its signed Release" >&2; exit 1; }
python3 -I "$HERE/carry.py" check-index "$WORK/Packages.gz" "$NV" "$HERE/packages.tsv" "$HERE/excluded.tsv"
mkdir "$WORK/debs" "$WORK/out" "$WORK/p"
: >"$WORK/nvidia-files.sha256"
# nvidia_deb FILE SIZE SHA256: NVIDIA's file, from NVDEBS or NVIDIA's repository, checked against the recorded hash
nvidia_deb() {
	local deb=${NVDEBS:+$NVDEBS/$1}
	if [ -z "$deb" ] || [ ! -f "$deb" ]; then
		deb=$WORK/debs/$1
		[ -f "$deb" ] || curl -fsS -o "$deb" "$NVREPO/$1"
	fi
	[ "$(stat -c %s "$deb")" = "$2" ] && [ "$(sha256sum <"$deb" | cut -d' ' -f1)" = "$3" ] ||
		{ echo "$deb is not NVIDIA's $1 ($3)" >&2; return 1; }
	printf '%s\n' "$deb"
}
read -r _ _ file size digest < <(awk -F'\t' '$1 == "nvidia-driver" && $2 == "amd64"' "$HERE/packages.tsv")
deb=$(nvidia_deb "$file" "$size" "$digest")
dpkg-deb --fsys-tarfile "$deb" | tar -xO ./usr/share/doc/nvidia-driver/copyright >"$WORK/copyright"
[ "$(sha256sum <"$WORK/copyright" | cut -d' ' -f1)" = "$COPYRIGHT_SHA256" ] ||
	{ echo "nvidia-driver's copyright file is not the one recorded ($COPYRIGHT_SHA256)" >&2; exit 1; }
n=0
while IFS=$'\t' read -r package arch file size digest; do
	case $package in '#'* | '') continue ;; esac
	deb=$(nvidia_deb "$file" "$size" "$digest")
	w=$WORK/p/${package}_$arch
	python3 -I "$HERE/carry.py" stage "$deb" "$NV" "$VERSION" "$HERE/packages.tsv" "$HERE/changelog" \
		"$HERE/README.sparky-stereo.in" "$WORK/copyright" "$w"
	PYTHONPATH=$TOOLKIT python3 -m lean.release build-tree "$w/tree" "$WORK/out" --preserve-plan "$w/plan.json" >/dev/null
	built=$WORK/out/${package}_${VERSION}_$arch.deb
	[ -f "$built" ] || { echo "lean.release built no $built" >&2; exit 1; }
	[ ! -e "$WORK/out/$package-lc-hr_${VERSION}_$arch.deb" ] ||
		{ echo "$package: Lean Code projected a file, so NVIDIA's files were not all kept" >&2; exit 1; }
	python3 -I "$HERE/carry.py" verify "$built" "$w/nvidia.json" >>"$WORK/nvidia-files.sha256"
	rm -rf "$w/tree"
	n=$((n + 1))
done <"$HERE/packages.tsv"
PYTHONPATH=$TOOLKIT python3 -m lean.release check-debs "$WORK"/out/*.deb
mkdir -p "$OUT"
cp -a "$WORK"/out/*.deb "$OUT"/
cp "$WORK/nvidia-files.sha256" "$OUT/nvidia-files.sha256"
sync
echo "built $n packages at $VERSION in $OUT; NVIDIA's files and their SHA-256: $OUT/nvidia-files.sha256"
