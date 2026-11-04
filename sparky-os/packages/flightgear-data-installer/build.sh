#!/bin/bash
#
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# Builds flightgear-data-installer: the small package that fetches FlightGear's own data release, checks its recorded
# SHA-256 and unpacks it where FlightGear looks (ORDER 399; Daniel, 2026-10-31: "we do not host it", "small downloader
# is better"). flightgear Depends on flightgear-data-all, which this package Provides at the version FlightGear needs.
# Needs only dpkg-deb; run it in a throwaway container or on any Debian.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=flightgear-data-installer
VERSION=2024.1.5-1
DATA=1:2024.1.5
W=$(mktemp -d "${TMPDIR:-/tmp}/$PKG-build.XXXXXX")
trap 'rm -rf "$W"' EXIT
COPY="$HERE/../../../tools/copy-recipe.py"
python3 "$COPY" "$HERE" "$W/inputs"
I=$W/inputs
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/sbin" "$D/usr/share/$PKG" "$D/usr/share/sparky/$PKG" "$D/usr/share/doc/$PKG" "$D/etc/default"
install -m 755 "$I/sbin/flightgear-data-installer" "$D/usr/sbin/flightgear-data-installer"
install -m 644 "$I/recorded" "$D/usr/share/$PKG/recorded"
install -m 644 "$I"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$I/etc/flightgear-data-installer" "$D/etc/default/flightgear-data-installer"
install -m 644 "$I/copyright" "$I/README.md" "$D/usr/share/doc/$PKG/"
install -m 755 "$I/postinst.sh" "$D/DEBIAN/postinst"
install -m 755 "$I/postrm.sh" "$D/DEBIAN/postrm"
printf '/etc/default/flightgear-data-installer\n' >"$D/DEBIAN/conffiles"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: bash (>= 4.3), ca-certificates, coreutils, curl, findutils, tar, util-linux, xz-utils
Provides: flightgear-data-all (= $DATA), flightgear-data-base (= $DATA), flightgear-data-ai (= $DATA), flightgear-data-models (= $DATA)
Conflicts: flightgear-data-all, flightgear-data-base, flightgear-data-ai, flightgear-data-models
Section: games
Priority: optional
Homepage: https://sparkylinux.org
Description: Fetches FlightGear's data from FlightGear's release page
  FlightGear needs about two gigabytes of data (aircraft, scenery, sounds,
  models). The edition does not host it: this small package downloads
  FlightGear's own data release 2024.1.5 from FlightGear's release page on
  SourceForge, checks it against the SHA-256 recorded here, and unpacks it in
  /usr/share/games/flightgear. A download that fails, a file that does not
  match or a computer with no network stops the installation and says what
  failed and what to do, in nine languages; nothing half-unpacked is left.
  Purging the package removes the data it unpacked.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | grep -v '^etc/' | sort | xargs md5sum) >"$D/DEBIAN/md5sums"
mkdir -p "$OUT"
"$HERE/../../repo/provenance.sh" --tree "$D"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.release build-tree "$D" "$OUT"
