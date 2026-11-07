#!/bin/bash
# Sparky Stereo OS: gtk4 4.24.1+ds-1+stereo3d1, Debian's 4.24.1+ds-1 with the stereo GtkGLArea patch, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/07
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor builds for the link gate, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck'
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's 4.24.1+ds-1 source package (the .dsc pins the files)
echo '43ca7e4305ba039a28451b818c5f2f0027ea998f3279fa2a18087e7a8146a640  /src/gtk4_4.24.1+ds-1.dsc' | sha256sum -c
cp /src/gtk4_4.24.1+ds-1.dsc /src/gtk4_4.24.1+ds-1.debian.tar.xz /src/gtk4_4.24.1+ds.orig.tar.xz .
dpkg-source -x gtk4_4.24.1+ds-1.dsc t >/dev/null
cd t
for p in /patches/stereo3d-gdk-dmabuf-export-open-fds.patch /patches/stereo3d-gtkglarea-stereo.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
# the patch brings the symbols' names into libgtk-4-1's list, in its order (dpkg-gensymbols checks them)
python3 - <<'SYMBOLS'
from pathlib import Path
p = Path('debian/libgtk-4-1.symbols.in')
s = p.read_text()
add = {
    ' gtk_gl_area_get_current_eye@Base 4.24.1+ds-1+stereo3d1\n': ' gtk_gl_area_get_error@Base 4.0.0\n',
    ' gtk_gl_area_get_stereo@Base 4.24.1+ds-1+stereo3d1\n gtk_gl_area_get_stereo_error@Base 4.24.1+ds-1+stereo3d1\n gtk_gl_area_get_stereo_shown@Base 4.24.1+ds-1+stereo3d1\n': ' gtk_gl_area_get_type@Base 4.0.0\n',
    ' gtk_gl_area_set_stereo@Base 4.24.1+ds-1+stereo3d1\n': ' gtk_gl_area_set_use_es@Base 4.0.0\n',
}
for new, before in add.items():
    assert s.count(before) == 1, before
    s = s.replace(before, new + before)
p.write_text(s)
SYMBOLS
# the protocol file the patch adds (MIT-CMU, by Daniel, as libstereo-declare ships it) is listed in debian/copyright
python3 - <<'COPYRIGHT'
from pathlib import Path
p = Path('debian/copyright')
s = p.read_text()
anchor = 'Files: debian/tests/run-with-display\n'
assert s.count(anchor) == 1
stanza = """Files: gdk/wayland/protocol/kde-stereo-content-v1.xml
Copyright: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
License: MIT-CMU

"""
license_text = """
License: MIT-CMU
 <copyright notice> By obtaining, using, and/or copying this software and/or
 its associated documentation, you agree that you have read, understood, and
 will comply with the following terms and conditions:
 .
 Permission to use, copy, modify, and distribute this software and its associated
 documentation for any purpose and without fee is hereby granted, provided
 that the above copyright notice appears in all copies, and that both that
 copyright notice and this permission notice appear in supporting documentation,
 and that the name of the copyright holder not be used in advertising or publicity
 pertaining to distribution of the software without specific, written permission.
 .
 THE COPYRIGHT HOLDER DISCLAIM ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
 INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT
 SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL
 DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM THE LOSS OF USE, DATA OR
 PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
 ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
"""
p.write_text(s.replace(anchor, stanza + anchor) + license_text)
COPYRIGHT
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('gtk4 (4.24.1+ds-1+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('gtk4 (4.24.1+ds-1) ')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
CHANGELOG
head -30 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/gtk4_4.24.1+ds-1+stereo3d1.dsc ../s1/gtk4_4.24.1+ds-1+stereo3d1.debian.tar.xz ../s1/gtk4_4.24.1+ds.orig.tar.xz .
dpkg-source -x gtk4_4.24.1+ds-1+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
# g-ir-scanner and gi-docgen read the gtk-doc comments, with their (transfer ...) and (nullable) annotations, from the C
# sources and headers of gtk, gdk and gsk: the typelib and the documentation need them, so those files stay as they are.
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 4.24.1+ds-1+stereo3d1+lc1 --toolkit /toolkit \
	--preserve-source 'gtk/*.c' 'g-ir-scanner and gi-docgen read the gtk-doc comments and annotations of the C sources and headers' \
	--preserve-source 'gtk/*.h' 'g-ir-scanner and gi-docgen read the gtk-doc comments and annotations of the C sources and headers' \
	--preserve-source 'gdk/*.c' 'g-ir-scanner and gi-docgen read the gtk-doc comments and annotations of the C sources and headers' \
	--preserve-source 'gdk/*.h' 'g-ir-scanner and gi-docgen read the gtk-doc comments and annotations of the C sources and headers' \
	--preserve-source 'gsk/*.c' 'g-ir-scanner and gi-docgen read the gtk-doc comments and annotations of the C sources and headers' \
	--preserve-source 'gsk/*.h' 'g-ir-scanner and gi-docgen read the gtk-doc comments and annotations of the C sources and headers'
apt-get -y update >/dev/null 2>&1
apt-get -y --no-install-recommends build-dep /work/lc/source >/work/build-dep.log 2>&1
# the link and start gate of lean.debhelper runs the rebuilt programs in a bubblewrap root
apt-get -y --no-install-recommends install bubblewrap >>/work/build-dep.log 2>&1
mkdir -p "$SPARKY_LC_SCRATCH"
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" /work/lc/source
useradd --create-home --uid 1000 builder
chown -R builder:builder /work
cd /work/lc/source
runuser -u builder -- env SPARKY_LC_PREVIOUS_DIR=/prev SPARKY_LC_ARCHIVE_CONFIG="$SPARKY_LC_ARCHIVE_CONFIG" SPARKY_LC_SCRATCH="$SPARKY_LC_SCRATCH" dpkg-buildpackage -us -uc -j4
cd /work/lc
PYTHONPATH=/toolkit python3 -m lean.release check-debs /work/lc/*+lc1_*.deb
rm -rf /work/lc/source/debian/build 2>/dev/null || true
