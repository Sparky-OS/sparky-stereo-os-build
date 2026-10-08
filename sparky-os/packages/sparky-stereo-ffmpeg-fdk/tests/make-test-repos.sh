#!/bin/bash
#
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/08
# Copyright 2026 under the GNU GPL3 License
# The test repositories of sparky-stereo-ffmpeg-fdk, flat, indexed by the real make-repo.sh (provenance stamps, Packages,
# Sources, Release with Origin "Sparky Stereo OS"):
#   repo2        the edition's ffmpeg-dmo 10:9.0.2-dmo1+stereo3d2: amd64 and i386 packages and the source package
#   repo2-no386  the same without the i386 packages (the helper must stop before the long build when they are missing)
#   repo3        repo2 plus 10:9.0.2-dmo1+stereo3d3, an "update" of FFmpeg: the +stereo3d2 packages with another version
#                and a source package whose only change is its changelog
# Usage: make-test-repos.sh   (T=work folder, A=amd64 .debs, I=i386 .debs, S=source files)
# Last update 2026/10/08
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
MAKE_REPO=${MAKE_REPO:-$HERE/../../../repo/make-repo.sh}
T=${T:-/mnt/build/mdmo2/fdktest}
A=${A:-/mnt/build/mdmo2/out/ffmpeg-amd64}
I=${I:-/mnt/build/mdmo2/out/ffmpeg-i386}
S=${S:-/mnt/build/mdmo2/out/source}
V2=10:9.0.2-dmo1+stereo3d2
V3=10:9.0.2-dmo1+stereo3d3
mkdir -p "$T"
for r in repo2 repo2-no386 repo3; do rm -rf "${T:?}/${r:?}"; mkdir -p "$T/$r/source"; done
cp "$A"/*_amd64.deb "$T/repo2/"
cp "$A"/*_amd64.deb "$T/repo2-no386/"
if ls "$I"/*_i386.deb >/dev/null 2>&1; then cp "$I"/*_i386.deb "$T/repo2/"; fi
cp "$S"/ffmpeg-dmo_9.0.2-dmo1+stereo3d2.dsc "$S"/ffmpeg-dmo_9.0.2-dmo1+stereo3d2.debian.tar.xz "$S"/ffmpeg-dmo_9.0.2.orig.tar.xz "$S"/ffmpeg-dmo_9.0.2.orig.tar.xz.asc "$T/repo2/source/"
cp "$T"/repo2/source/* "$T/repo2-no386/source/"

# the update: version only for the binaries, a new changelog entry for the source
W=$(mktemp -d "$T/v3.XXXXXX")
trap 'rm -rf "${W:?}"' EXIT
cp "$T"/repo2/*.deb "$T/repo3/"
cp "$T"/repo2/source/* "$T/repo3/source/"
for d in "$T"/repo2/*.deb; do
	b=$(basename "$d")
	n=${b//stereo3d2/stereo3d3}
	python3 "$HERE/relabel-version.py" "$d" "$V2" "$V3" "$T/repo3/$n"
done
(
	cd "$W"
	cp "$S"/ffmpeg-dmo_9.0.2-dmo1+stereo3d2.dsc "$S"/ffmpeg-dmo_9.0.2-dmo1+stereo3d2.debian.tar.xz "$S"/ffmpeg-dmo_9.0.2.orig.tar.xz "$S"/ffmpeg-dmo_9.0.2.orig.tar.xz.asc .
	dpkg-source --no-check --no-preparation -x ffmpeg-dmo_9.0.2-dmo1+stereo3d2.dsc >/dev/null 2>&1
	{
		printf 'ffmpeg-dmo (%s) unstable; urgency=medium\n\n  * Test update of the edition'"'"'s FFmpeg: only this entry is new.\n\n -- Daniel Campos Ramos <Capitain_Jack@yahoo.com>  Thu, 08 Oct 2026 12:00:00 +0000\n\n' "$V3"
		cat ffmpeg-dmo-9.0.2/debian/changelog
	} >ffmpeg-dmo-9.0.2/debian/changelog.new
	mv ffmpeg-dmo-9.0.2/debian/changelog.new ffmpeg-dmo-9.0.2/debian/changelog
	(cd ffmpeg-dmo-9.0.2 && dpkg-source --before-build . >/dev/null 2>&1)
	dpkg-source -b ffmpeg-dmo-9.0.2 >/dev/null 2>&1
	cp ffmpeg-dmo_9.0.2-dmo1+stereo3d3.dsc ffmpeg-dmo_9.0.2-dmo1+stereo3d3.debian.tar.xz "$T/repo3/source/"
)
for r in repo2 repo2-no386 repo3; do
	"$MAKE_REPO" "$T/$r" >/dev/null
	echo "$r: $(grep -c '^Package:' "$T/$r/Packages") packages, $(grep -c '^Package:' "$T/$r/Sources") source packages; Release: $(grep -E '^(Origin|Label)' "$T/$r/Release" | tr '\n' ' ')"
done
