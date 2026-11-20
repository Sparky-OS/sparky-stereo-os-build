#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare fork source using Debian's shared-library route and DMO's features."""
import json
import os
from pathlib import Path
import subprocess
import sys

recipe = Path(__file__).resolve().parent
toolkit = recipe.parents[1]
sys.path.insert(0, str(toolkit / 'repo'))
import reproducible

source = Path(sys.argv[1]).resolve()
stamp = reproducible.recipe_epoch([recipe])
info = json.loads((source / 'debian/sparky-fork-source.json').read_text())
version = '1:' + info['upstream_version'] + '-dmo3+stereo3d2'
env = os.environ | {'SOURCE_DATE_EPOCH': str(stamp), 'PYTHONPATH': str(toolkit),
                    'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)', 'DEBEMAIL': 'Capitain_Jack@yahoo.com'}
control = source / 'debian/control'
t = control.read_text()
t = t.replace('libx264-dev (>= 3:0.155~)', 'libx264-dev (>= 4:0.165.3222+gitb35605a-dmo5+stereo3d1+lc1)')
t = t.replace(' libmp3lame-dev,',
              ' libavcodec-dev (>= 10:9.0.2-dmo1+stereo3d16+lc1), libavformat-dev (>= 10:9.0.2-dmo1+stereo3d16+lc1),\n'
              ' libavfilter-dev, libavutil-dev, libswscale-dev, libswresample-dev, libdvdread-dev,\n'
              ' libx265-dev (>= 1:4.3-dmo1+stereo3d2+lc1), libstereo-gtk-dev (>= 1.23.2-1+lc1), zlib1g-dev, libmp3lame-dev,')
# shlibs give only libavcodec63 (>= 10:9.0.2), which the published +15 meets: on a machine with the i386 FFmpeg
# libraries apt then kept the cohort back and Stereo HandBrake ran on +15 (ORDER 742). The floors keep the two programs
# on the libraries that carry HandBrake's imported patches and the frame packing API.
cohort = '10:9.0.2-dmo1+stereo3d16~'
floors = ', '.join(f'{name} (>= {cohort})' for name in (
    'libavcodec63', 'libavfilter12', 'libavformat63', 'libavutil61', 'libswresample7', 'libswscale10'))
floors += ', libx264-165 (>= 4:0.165.3222+gitb35605a-dmo5+stereo3d1~), libx265-30219 (>= 1:4.3-dmo1+stereo3d2~)'
if t.count('Depends: ${shlibs:Depends},') != 2:
    raise SystemExit('expected the two program stanzas of handbrake-cli and handbrake-gtk')
t = t.replace('Depends: ${shlibs:Depends},', 'Depends: ${shlibs:Depends}, ' + floors + ',')
# ghb plays the live preview through GTK's GStreamer backend (GstPlay), which ends the program when GStreamer's playbin
# element is missing; playbin is in gstreamer1.0-plugins-base (libgstplayback.so). A dependency a feature needs is a
# Depends (ORDER 742). libstereo-gtk1 1.23.2 declares the preview's 3D area again after "Enable 3D" is turned back on.
gtk_stanza = t.index('Package: handbrake-gtk')
gtk_depends = t.index('Depends: ${shlibs:Depends}, ', gtk_stanza)
t = t[:gtk_depends] + 'Depends: ${shlibs:Depends}, gstreamer1.0-plugins-base, libstereo-gtk1 (>= 1.23.2),' + \
    t[gtk_depends + len('Depends: ${shlibs:Depends},'):]
control.write_text(t)
rules = source / 'debian/rules'
t = rules.read_text()
# The fork keeps upstream's GNU tuple parser rather than DMO's vendorless parser.
t = t.replace('--host=$(DEB_HOST_GNU_TYPE)', '--host=$(DEB_HOST_GNU_TYPE:%-linux-gnu=%-unknown-linux-gnu)')
t = t.replace('--build=$(DEB_BUILD_GNU_TYPE)', '--build=$(DEB_HOST_GNU_TYPE:%-linux-gnu=%-unknown-linux-gnu)')
# debhelper builds in configure's folder, which is named by that same tuple.
t = t.replace('dh $@ -B$(DEB_HOST_GNU_TYPE)', 'dh $@ -B$(DEB_HOST_GNU_TYPE:%-linux-gnu=%-unknown-linux-gnu)')
rules.write_text(t)
# The link gate counts every imported symbol named "stereo". deb-multimedia's HandBrake linked its own FFmpeg statically,
# so its programs imported libspeex's stereo decoding; with the shared FFmpeg, libavcodec63 imports it (nm -D), and the
# programs no longer do. Speex stereo decoding is kept; the import moved to the library.
(source / 'debian/sparky-lean-retired-stereo-imports').write_text(
    'speex_decode_stereo_int Speex stereo decoding moved with FFmpeg into the shared libavcodec63, which imports it\n'
    'speex_std_stereo_request_handler Speex stereo decoding moved with FFmpeg into the shared libavcodec63, which imports it\n')
subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', version,
                '--distribution', 'UNRELEASED',
                'Build the Sparky-OS HandBrake fork against shared edition libraries, preserving all three binary names and encoder features. '
                'An MV-HEVC source is scanned and encoded as one full side-by-side frame; views in turn are paired from the source\'s first frame; '
                '"Enable 3D" comes back on in the preview; a missing GStreamer playbin is said, and handbrake-gtk Depends on gstreamer1.0-plugins-base.'],
               cwd=source, env=env, check=True)
subprocess.run([sys.executable, '-m', 'lean.debian_prepare', str(source), version + '+lc1', '--toolkit', str(toolkit),
                '--build-dependency', 'bubblewrap', '--preserve-source', 'gtk/*',
                'GTK translation and resource generators consume authored source and translator comments.'], env=env, check=True)
reproducible.normalize_tree(source, stamp)
