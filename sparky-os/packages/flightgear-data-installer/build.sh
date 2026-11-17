#!/bin/bash
#
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# Builds flightgear-data-installer: the small package that fetches FlightGear's own data release, checks its recorded
# SHA-256 and unpacks it where FlightGear looks (ORDER 399; Daniel, 2026-10-31: "we do not host it", "small downloader
# is better"). flightgear Depends on flightgear-data-all, which this package Provides at the version FlightGear needs.
# Needs dpkg-dev, python3 and sparky-stereo-problems (it makes the problem catalogs); the .debs and the source package (.dsc and tarball) come out together. Run it in a throwaway container or on any Debian.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=flightgear-data-installer
VERSION=2024.1.5-2
DATA=1:2024.1.5
W=$(mktemp -d "${TMPDIR:-/tmp}/$PKG-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$W/inputs"
I=$W/inputs
# the install-time download this package declares in its control file is the recorded one (size and source), read once
# from the file the program reads, so the two cannot differ
# shellcheck source=/dev/null
. "$I/recorded"
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/sbin" "$D/usr/share/$PKG" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" "$D/etc/default" "$D/usr/lib/systemd/catalog"
install -m 755 "$I/sbin/flightgear-data-installer" "$D/usr/sbin/flightgear-data-installer"
install -m 644 "$I/recorded" "$D/usr/share/$PKG/recorded"
install -m 644 "$I"/lang/* "$D/usr/share/sparky/$PKG/"
# the messages of the time zone problem, in ten languages, as journal catalogs the problems engine reads (ORDER 645)
sparky-stereo-problems catalog "$PKG" "$I/problems" "$D/usr/lib/systemd/catalog" --subject LOCAL1
install -m 644 "$I/etc/flightgear-data-installer" "$D/etc/default/flightgear-data-installer"
install -m 644 "$I/copyright" "$I/README.md" "$D/usr/share/doc/$PKG/"
install -m 755 "$I/postinst.sh" "$D/DEBIAN/postinst"
install -m 755 "$I/postrm.sh" "$D/DEBIAN/postrm"
printf '/etc/default/flightgear-data-installer\n' >"$D/DEBIAN/conffiles"
SIZE_BYTES=$SIZE
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: bash (>= 4.3), ca-certificates, curl, sparky-stereo-problems (>= 0.1.2), xz-utils
Provides: flightgear-data-all (= $DATA), flightgear-data-base (= $DATA), flightgear-data-ai (= $DATA), flightgear-data-models (= $DATA)
Sparky-Install-Download-Size: $SIZE_BYTES
Sparky-Install-Download-Source: $URL
Section: games
Priority: optional
Homepage: https://sparkylinux.org
Description: Fetches FlightGear's data from FlightGear's release page
  FlightGear needs about two gigabytes of data (aircraft, scenery, sounds,
  models). The edition does not host it: this small package downloads
  FlightGear's own data release 2024.1.5 from FlightGear's release page on
  SourceForge in parallel byte ranges, checks it against the SHA-256 recorded here, and unpacks it in
  /usr/share/games/flightgear. A download that fails, a file that does not
  match or a computer with no network stops the installation and says what
  failed and what to do, in ten languages; nothing half-unpacked is left.
  Removing the package removes the data it unpacked. Debian's own
  flightgear-data packages, when they hold the same data, are left where they
  are, and a Timezone folder that is a link into the system's time zone files is
  never followed: it is kept as a problem with a repair.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | grep -v '^etc/' | sort | xargs md5sum) >"$D/DEBIAN/md5sums"
mkdir -p "$OUT" "$W/authoring"
cp -a "$I/." "$W/authoring/"
mkdir -p "$W/authoring/build-tools"
cp "$COPY" "$W/authoring/build-tools/"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$W/authoring" --build-dependency sparky-stereo-problems
