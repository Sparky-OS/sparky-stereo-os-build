#!/bin/sh
# Indexes our packages as a flat apt repository with its own origin, "Sparky Stereo OS",
# which the edition pins above Debian (../apt/sparky-stereo, shipped by the sparky-stereo-apt package) so updates keep the
# stereo stack. While developing it lives in /K3D/temp/sparky-os/repo, which the VM sees
# as /srv/sparky-work/repo:
#   deb [trusted=yes] file:/srv/sparky-work/repo ./
# (unsigned while developing; the published repository will be signed).
# carried/ holds unmodified Debian packages we carry for a while (not re-signed), e.g.
# libcapi20-3t64, which Wine 10 in testing needs after isdnutils left testing.
# source/ holds the source packages (.dsc and the files it names); they are indexed as Sources
# ("Directory: source"), so that "deb-src [trusted=yes] file:... ./" gives apt-get source and
# sparky-stereo-ffmpeg-fdk (which builds the edition's FFmpeg on the user's computer) the same
# source the binaries were built from.
set -eu
R=${1:-/K3D/temp/sparky-os/repo}
# Builders finish provenance before Lean Code and archive checksums. Indexing
# must not rewrite existing archives, including old unmarked development builds.
cd "$R"
apt-ftparchive packages . >Packages
gzip -9kf Packages
if ls source/*.dsc >/dev/null 2>&1; then
	# only the files of source/ itself (apt-ftparchive would go into source/superseded too): a folder of links
	L=$(mktemp -d "${TMPDIR:-/tmp}/sources-index.XXXXXX")
	mkdir "$L/source"
	for f in source/*; do
		if [ -f "$f" ]; then ln -s "$PWD/$f" "$L/source/"; fi
	done
	(cd "$L" && apt-ftparchive sources source 2>"$L/err") >Sources
	grep -v -i 'override' "$L/err" >&2 || true
	rm -rf "${L:?}"
	gzip -9kf Sources
else
	rm -f Sources Sources.gz
fi
apt-ftparchive -o APT::FTPArchive::Release::Origin="Sparky Stereo OS" \
	-o APT::FTPArchive::Release::Label="Sparky Stereo OS" \
	-o APT::FTPArchive::Release::Description="Sparky Stereo OS: the stereo stack and the edition's own packages" \
	release . >Release
grep -c '^Package:' Packages
