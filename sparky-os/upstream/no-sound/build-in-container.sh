#!/bin/bash
# Sparky Stereo OS: builds one +lc1 source of ORDER 579 through Lean Code, in a throwaway container (ns-579-build:*).
# Created by Daniel Ramos (Capitain Jack) 2026/11/15
# Copyright 2026 under the GNU GPL3 License
# Inside the container: /src holds the .dsc with its orig tarball and Debian tarball (read only), /work the job folder (the
# new packages and the build log land here), /repo the published repository (read only), /stage the flat folder of the
# earlier packages of this lane (the stereo layer), /toolkit this build tree's sparky-os (read only), /prev the earlier
# +lc1 .deb files for the link gate's siblings, /archive the link gate's sources.json.
# Usage: build-in-container.sh DSC_NAME
set -euo pipefail
trap 'chown -R 1000:1000 /work' EXIT
ulimit -c 1
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
DSC=$1
printf 'deb [signed-by=/repo/sparky-stereo-repo.asc] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
[ -s /stage/Packages.gz ] && printf 'deb [trusted=yes] file:/stage ./\n' > /etc/apt/sources.list.d/lane.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n\nPackage: *\nPin: origin ""\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cp /run/pins/sparky-stereo-only-ours /etc/apt/preferences.d/ 2>/dev/null || true
apt-get -y update >/dev/null 2>&1 || { sleep 10; apt-get -y update >/dev/null; }
mkdir -p /work/build && cd /work/build
cp /src/* .
dpkg-source -x "$DSC" source >/dev/null
apt-get -y --no-install-recommends build-dep ./source >/work/build-dep.log 2>&1 || { tail -30 /work/build-dep.log; exit 1; }
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(dpkg-parsechangelog -l source/debian/changelog -S Timestamp)}
mkdir -p "${SPARKY_LC_SCRATCH:=/work/link-scratch}"
# the link gate's siblings: the lane's own unpublished libraries (the stereo layer) the package was built against
if [ "${DSC#stereo-layer_}" = "$DSC" ] && ls /stage/libstereo-*1_*.deb >/dev/null 2>&1; then
	ls /stage/libstereo-*1_*_amd64.deb > /work/siblings.txt
	export SPARKY_LC_SIBLINGS_FILE=/work/siblings.txt
fi
id builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
# binaries only (also the architecture-independent ones) from the supplied descriptor: a plain dpkg-buildpackage packs the source again, with timestamps
# the build moved, so the staged .dsc and tarballs would not be the ones the source script made (lessons-2026-11, "Two staged works on one library")
cd source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" \
	${SPARKY_LC_SIBLINGS_FILE:+SPARKY_LC_SIBLINGS_FILE=$SPARKY_LC_SIBLINGS_FILE} PATH="$PATH" dpkg-buildpackage -b -us -uc -j4
cd /work/build
PYTHONPATH=/toolkit python3 -m lean.release check-debs ./*+lc1_*.deb
PYTHONPATH=/toolkit python3 -m lean.release check-identity ./*+lc1_*.deb
ls
