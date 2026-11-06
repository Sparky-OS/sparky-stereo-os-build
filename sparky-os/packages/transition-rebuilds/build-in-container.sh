#!/bin/bash
# Sparky Stereo OS: rebuilds one published +lc1 source package, unchanged, for a library transition in Debian testing.
# Created by Daniel Ramos (Capitain Jack) 2026/10/31
# Copyright 2026 under the GNU GPL3 License
# Runs inside a freshly updated debian:testing build container; build.sh starts it. /work is the job folder, /src the
# published +lc1 source package (its .dsc and every file it names), /prev the earlier +lc1 builds and the library the
# transition took out of the archive (the link gate's predecessor universe), /entry the changelog entry, /toolkit the build
# tree's sparky-os folder, /repo the edition's published tree (read only) and /archive the link gate's sources.json with
# the public keyrings it names. DSC names the published .dsc, DSC_SHA256 its checksum, PLAIN_OPTIONS the
# plain-from-lc.py option the source's shape needs (empty, --edition-entry, --lc-successor or --no-build-depends). The source's
# preparation (plain source, entry, +lc1 source, the published Lean Code preserve plan carried over) is prepare-lc-source.sh (ORDER 433).
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS=parallel=4
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
: "${DSC:?}" "${DSC_SHA256:?}" "${PLAIN_OPTIONS?}"
printf 'deb [signed-by=/archive/sparky-stereo-repo.gpg] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/archive/deb-multimedia-keyring.gpg] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
bash /tools/prepare-lc-source.sh
cd /work/lc/source
apt-get -y update > /work/apt-update.log 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source > /work/build-dep.log 2>&1 || { tail -40 /work/build-dep.log; exit 1; }
dpkg-query -W -f='${Package}\t${Version}\n' > /work/build-environment.tsv
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >> /work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
id -u builder >/dev/null 2>&1 || useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" \
	SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4 > /work/build.log 2>&1 || { tail -60 /work/build.log; exit 1; }
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
for deb in /work/lc/*+lc1_*.deb; do
	printf '%s\t%s\n' "$(basename "$deb")" "$(dpkg-deb -f "$deb" Depends)"
done > /work/depends.tsv
