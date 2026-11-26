#!/bin/bash
# Sparky Stereo OS: gtk+3.0 3.24.52-3+stereo3d1, Debian's 3.24.52-3 with the stereo GtkGLArea patches (Wayland and X11, depth and
# colour state) and the demo, built with Lean Code.
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# Runs inside the Lean Code migration container; build.sh starts it. /work is the job folder, /src Debian's source package,
# /prev the predecessor builds for the link gate, /patches this folder's patches.
trap 'chown -R 1000:1000 /work' EXIT
set -euo pipefail
: "${SOURCE_DATE_EPOCH:?a source is dated by its recipe, never by the clock: run this through build-provenance.sh (sparky_provenance_init) or export SOURCE_DATE_EPOCH}" "${SOURCE_DATE_RFC2822:?see SOURCE_DATE_EPOCH}"
# libgtk-3-0-udeb (Debian-Installer's GTK front end, which the edition's installer, Calamares, does not use) is not built: its
# udeb dependencies cannot be solved with the deb packages in one link-gate root (libc6-udeb and libc6 ship the same files)
export DEBIAN_FRONTEND=noninteractive DEB_BUILD_OPTIONS='parallel=4 nocheck' DEB_BUILD_PROFILES=noudeb
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
printf 'deb [trusted=yes] file:/repo mashtabba main\n' > /etc/apt/sources.list.d/edition.list
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' > /etc/apt/sources.list.d/multimedia.list
printf 'deb https://deb.debian.org/debian testing contrib non-free non-free-firmware\n' > /etc/apt/sources.list.d/debian-extra-components.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/edition
cd /work
mkdir s1 && cd s1
# Debian's 3.24.52-3 source package (the .dsc pins the files)
echo '86d87e43ebdca5ea8fcc1ba8da8cba3dcc632d2b575f87925302707a9edfc2d5  /src/gtk+3.0_3.24.52-3.dsc' | sha256sum -c
cp /src/gtk+3.0_3.24.52-3.dsc /src/gtk+3.0_3.24.52-3.debian.tar.xz /src/gtk+3.0_3.24.52.orig.tar.xz .
dpkg-source -x gtk+3.0_3.24.52-3.dsc t >/dev/null
cd t
for p in /patches/stereo3d-gdk-color-state.patch /patches/stereo3d-gtkglarea-stereo.patch /patches/stereo3d-gtk3-demo-glarea-stereo.patch /patches/stereo3d-testsuite-glarea.patch; do
	cp "$p" debian/patches/
	basename "$p" >> debian/patches/series
done
# the patches bring new symbols into libgdk-3.so.0 and libgtk-3.so.0: each goes into libgtk-3-0t64's list before the first
# name of its library that sorts after it (dh_makeshlibs runs dpkg-gensymbols with -c4, which fails on a symbol not listed)
python3 - <<'SYMBOLS'
from pathlib import Path
p = Path('debian/libgtk-3-0t64.symbols')
version = '3.24.52-3+stereo3d1'
new = {
    'libgdk-3.so.0': '''gdk_cicp_params_build_color_state gdk_cicp_params_get_color_primaries gdk_cicp_params_get_matrix_coefficients
        gdk_cicp_params_get_range gdk_cicp_params_get_transfer_function gdk_cicp_params_get_type gdk_cicp_params_new
        gdk_cicp_params_set_color_primaries gdk_cicp_params_set_matrix_coefficients gdk_cicp_params_set_range
        gdk_cicp_params_set_transfer_function gdk_cicp_range_get_type gdk_color_state_create_cicp_params
        gdk_color_state_equal gdk_color_state_get_rec2100_linear gdk_color_state_get_rec2100_pq gdk_color_state_get_srgb
        gdk_color_state_get_srgb_linear gdk_color_state_get_type gdk_color_state_ref gdk_color_state_unref
        gdk_memory_format_get_type'''.split(),
    'libgtk-3.so.0': '''gtk_gl_area_eye_get_type gtk_gl_area_get_color_state gtk_gl_area_get_current_eye gtk_gl_area_get_format
        gtk_gl_area_get_stereo gtk_gl_area_get_stereo_error gtk_gl_area_get_stereo_shown gtk_gl_area_get_stereo_view_size
        gtk_gl_area_set_color_state gtk_gl_area_set_format gtk_gl_area_set_stereo gtk_gl_area_set_stereo_view_size'''.split(),
}
lines = p.read_text().splitlines(keepends=True)
heads = [i for i, l in enumerate(lines) if not l.startswith((' ', '*', '|', '#')) and l.strip()]
out = list(lines)
for lib, names in new.items():
    start = next(i for i in heads if lines[i].startswith(lib + ' '))
    end = next((i for i in heads if i > start), len(lines))
    for name in sorted(names):
        assert not any(l.split('@')[0].strip() == name for l in lines[start:end]), name
        entry = f' {name}@Base {version}\n'
        block = [i for i in range(start + 1, end) if lines[i].startswith(' ') and '@' in lines[i]]
        after = next((i for i in block if lines[i].split('@')[0].strip() > name), end)
        out.insert(out.index(lines[after]) if after < end else out.index(lines[end - 1]) + 1, entry)
p.write_text(''.join(out))
SYMBOLS
# the new files are the edition's, under GTK's own licence (LGPL-2+)
python3 - <<'COPYRIGHT'
from pathlib import Path
p = Path('debian/copyright')
s = p.read_text()
anchor = '\nFiles: debian/tests/run-with-display\n'
assert s.count(anchor) == 1
stanza = """
Files: gdk/gdkcolorstate.c gdk/gdkcolorstate.h gtk/gtkglareastereo.c gtk/gtkglareastereoprivate.h testsuite/gtk/glarea.c
Copyright: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
License: LGPL-2+
"""
p.write_text(s.replace(anchor, stanza + anchor))
COPYRIGHT
# stereo areas load libstereo-declare when the first one asks; they are a designed feature, so libgtk-3-0t64 depends on it
# (memory design-check-every-default: a dependency a designed feature needs is a Depends); 1.7.0 declares X11 children
# and their place, which this build uses with the Wayland declaration
python3 - <<'CONTROL'
from pathlib import Path
p = Path('debian/control')
s = p.read_text()
old = "         libgtk-3-common (>= ${source:Upstream-Version}),\n"
assert s.count(old) == 1
p.write_text(s.replace(old, old + "         libstereo-declare1 (>= 1.7.0),\n"))
CONTROL
python3 - <<'CHANGELOG'
from pathlib import Path
import os
p = Path('debian/changelog')
entry = Path('/tools/changelog-stereo3d1.txt').read_text()
assert entry.startswith('gtk+3.0 (3.24.52-3+stereo3d1) unstable;'), entry[:60]
assert p.read_text().startswith('gtk+3.0 (3.24.52-3) ')
p.write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  ' + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + p.read_text())
CHANGELOG
head -30 debian/changelog
cd ..
python3 /run/reproducible.py normalize-tree "$SOURCE_DATE_EPOCH" t
dpkg-source -b t >/dev/null
rm -rf t
ls
mkdir -p /work/lc && cd /work/lc
cp ../s1/gtk+3.0_3.24.52-3+stereo3d1.dsc ../s1/gtk+3.0_3.24.52-3+stereo3d1.debian.tar.xz ../s1/gtk+3.0_3.24.52.orig.tar.xz .
dpkg-source -x gtk+3.0_3.24.52-3+stereo3d1.dsc /work/lc/source >/dev/null
cd /work/lc/source
# g-ir-scanner and gtk-doc read the doc comments, with their annotations, from the C sources and headers of gdk (its
# backends included), gtk and libgail-util: the typelib and the documentation need them, so those files stay as they are.
# gtk3-demo shows the source of each demo and reads its title from the first comment; gtk-3-examples ships the examples
# as sources to read; the test programs and their data are read as text.
PYTHONPATH=/toolkit python3 -m lean.debian_prepare /work/lc/source 3.24.52-3+stereo3d1+lc1 --toolkit /toolkit \
	--preserve-source 'gtk/*.c' 'g-ir-scanner and gtk-doc read the doc comments and annotations of the C sources and headers' \
	--preserve-source 'gtk/*.h' 'g-ir-scanner and gtk-doc read the doc comments and annotations of the C sources and headers' \
	--preserve-source 'gdk/*.c' 'g-ir-scanner and gtk-doc read the doc comments and annotations of the C sources and headers' \
	--preserve-source 'gdk/*.h' 'g-ir-scanner and gtk-doc read the doc comments and annotations of the C sources and headers' \
	--preserve-source 'libgail-util/*' 'gtk-doc reads the doc comments of libgail-util for libgail-3-doc' \
	--preserve-source 'demos/*' 'gtk3-demo shows the source of each demo and takes its title from its first comment' \
	--preserve-source 'examples/*' 'gtk-3-examples ships the examples as sources to be read' \
	--preserve-source 'testsuite/*' 'the test programs and their data are read as text and compared byte for byte' \
	--preserve-source 'tests/*' 'the interactive test programs are sources to read'
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
