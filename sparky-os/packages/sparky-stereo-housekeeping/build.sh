#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Builds sparky-stereo-housekeeping: BleachBit's "System mail" cleaner (ORDER 415) and, in time, the edition's other
# cleaners. Needs dpkg-deb, python3 and sparky-stereo-problems (its catalog command).
# Last update 2026/11/06
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-${SPARKY_REPO_DIR:?}}
PKG=sparky-stereo-housekeeping
VERSION=$(sed -n '2s/^  Version \([^ ]*\) .*/\1/p' "$HERE/CHANGELOG")
VERSION=${VERSION}+lc1
W=$(mktemp -d "${TMPDIR:-/tmp}/housekeeping.XXXXXX")
trap 'rm -rf "$W"' EXIT
D=$W/$PKG
mkdir -p "$D/DEBIAN" "$D/usr/lib/$PKG" "$D/usr/share/$PKG/po" "$D/usr/share/doc/$PKG" "$D/usr/bin" \
	"$D/usr/share/sparky/$PKG" "$D/usr/lib/systemd/catalog"
# the package's own messages, word for word, as journal catalogs the engine reads in the person's language (ORDER 350)
sparky-stereo-problems catalog $PKG "$HERE/lang" "$D/usr/lib/systemd/catalog" --subject LOCAL11
find "$D/usr/lib/systemd" -type d -exec chmod 755 {} + && find "$D/usr/lib/systemd" -type f -exec chmod 644 {} +
install -m 755 "$HERE/bin/sparky-stereo-housekeeping" "$D/usr/bin/"
install -m 755 "$HERE/lib/system_mail.py" "$D/usr/lib/$PKG/system_mail.py"
install -m 644 "$HERE/lib/problems.py" "$D/usr/lib/$PKG/problems.py"
install -m 644 "$HERE/share/system_mail.xml.in" "$D/usr/share/$PKG/system_mail.xml.in"
install -m 644 "$HERE"/po/*.po "$D/usr/share/$PKG/po/"
install -m 644 "$HERE"/lang/* "$D/usr/share/sparky/$PKG/"
install -m 644 "$HERE/README.md" "$D/usr/share/doc/$PKG/README.md"
cat >"$D/usr/share/doc/$PKG/copyright" <<'EOS'
Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s):
    Paweł "pavroo" Pijanowski <pavroo@onet.eu>
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: *
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3

The cleaner follows the format and the style of BleachBit's cleaners (Andrew Ziem and its contributors,
https://www.bleachbit.org, GPL-3+) and is meant to be offered to the project.

License:

    This package is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This package is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this package; if not, see <http://www.gnu.org/licenses/>.

On Debian systems, the complete text of the GNU General
Public License can be found in `/usr/share/common-licenses/GPL-3'.
EOS
chmod 644 "$D/usr/share/doc/$PKG/copyright"
# The cleaner depends on what is installed and on Debian's catalogs, so it is written when the package is configured
# and whenever dpkg says a mail program or bleachbit changed. A failure is said and kept (the engine), and the package
# configures: nothing else on the system depends on the cleaner.
cat >"$D/DEBIAN/postinst" <<'EOS'
#!/bin/sh
set -e
L=/usr/lib/sparky-stereo-housekeeping
if [ "$1" = configure ] || [ "$1" = triggered ]; then
	python3 $L/problems.py run system-mail LOCAL1 --repair python3 $L/system_mail.py refresh -- python3 $L/system_mail.py refresh || :
fi
exit 0
EOS
cat >"$D/DEBIAN/prerm" <<'EOS'
#!/bin/sh
set -e
# the cleaner and the catalogs go while this package's files can still be run; Debian's catalogs come back
if [ "$1" = remove ] || [ "$1" = deconfigure ]; then
	python3 /usr/lib/sparky-stereo-housekeeping/system_mail.py remove
fi
exit 0
EOS
cat >"$D/DEBIAN/postrm" <<'EOS'
#!/bin/sh
set -e
# a problem of a package that is gone cannot be repaired by it (ORDER 350)
if [ "$1" = remove ] && command -v sparky-stereo-problems >/dev/null; then
	sparky-stereo-problems clear --all sparky-stereo-housekeeping || :
fi
exit 0
EOS
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/prerm" "$D/DEBIAN/postrm"
# bleachbit's cleaners folder (bleachbit installed or upgraded) and one file of each mail program (installed, removed)
printf 'interest-noawait %s\n' /usr/share/bleachbit/cleaners /usr/sbin/exim4 /usr/sbin/exim_dbmbuild /usr/sbin/postfix \
	/usr/sbin/nullmailer-send /usr/sbin/dma /usr/bin/msmtp /usr/sbin/ssmtp >"$D/DEBIAN/triggers"
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOS
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: python3, gettext, dpkg, sparky-stereo-problems (>= 0.1.0)
Recommends: bleachbit
Section: admin
Priority: optional
Homepage: https://sparkylinux.org
Description: Sparky Stereo OS cleaners for BleachBit
  A "System mail" cleaner for BleachBit, never ticked on its own: it empties
  the local mailbox (your own, or every one as administrator), deletes
  dead.letter, and deletes the queues that mail programs no longer
  installed (exim4, postfix, nullmailer, dma, msmtp) left behind. The queue
  of an installed mail program is never touched. Each option says what kind
  of mail it holds and that a person's own mail in the local mailbox is
  deleted too.
  .
  The cleaner's text is translated in the nine languages of the edition,
  added to Debian's translation of BleachBit, which keeps its own wording.
EOS
(cd "$D" && find . -path ./DEBIAN -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' '\0' | xargs -0 md5sum >DEBIAN/md5sums)
mkdir -p "$OUT"
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE"
echo "built $OUT/${PKG}_${VERSION}_all.deb"
