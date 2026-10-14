#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Add the accepted patches to unmodified Debian testing source packages."""
from pathlib import Path
import difflib
import re
import subprocess
import sys

repo = Path('/workspace/gl-stereo')
base = Path('/build/sources')
credit = 'Sparky Stereo OS, Daniel Ramos\'s edition of SparkyLinux (by Paweł "pavroo" Pijanowski)'
maintainer = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
for name, version, patch, dependency in (
    ('xscreensaver', '6.09+dfsg1-2', 'savers/rocks-sbs.patch', 'libstereo-declare-dev (>= 1.1.0)'),
    ('kscreenlocker', '6.7.4-1', 'plasma/patches/kscreenlocker-stereo-background.patch', 'libstereoshow-dev (>= 0.2.0)'),
    ('plasma-desktop', '4:6.7.4-1', 'plasma/patches/plasma-desktop-stereo-background.patch', ''),
):
    if sys.argv[1:] and name not in sys.argv[1:]:
        continue
    upstream = version.split(':')[-1].rsplit('-', 1)[0]
    tree = base / f'{name}-{upstream}'
    debian = tree / 'debian'
    assert '+stereo3d' not in (debian/'changelog').read_text().splitlines()[0], 'already prepared'
    text = (debian/'control').read_text()
    text = re.sub(r'^Maintainer: (.*)$', lambda m: f'Maintainer: {maintainer}\nXSBC-Original-Maintainer: {m[1]}', text, flags=re.M)
    text = re.sub(r'^Homepage: .*$', 'Homepage: https://sparkylinux.org\nXSBC-Comment: ' + credit, text, flags=re.M)
    if dependency:
        text = text.replace('Build-Depends: ', f'Build-Depends: {dependency},\n               ', 1)
    paragraphs = text.strip().split('\n\n')
    for i, paragraph in enumerate(paragraphs):
        if paragraph.startswith('Package:'):
            paragraphs[i] += '\n .\n ' + credit
    (debian/'control').write_text('\n\n'.join(paragraphs)+'\n')
    copyright_file = debian/'copyright'
    paragraphs = copyright_file.read_text().strip().split('\n\n')
    found = False
    for i, paragraph in enumerate(paragraphs):
        if paragraph.splitlines()[0] == 'Files: debian/*':
            paragraphs[i] = paragraph.replace('\nLicense:', '\n           2026 Daniel Ramos\nLicense:', 1) + '\nComment: ' + credit
            found = True
    if not found:
        paragraphs.append('Files: debian/*\nCopyright: 2026 Daniel Ramos\nLicense: GPL-2.0-or-later\nComment: ' + credit)
    copyright_file.write_text('\n\n'.join(paragraphs)+'\n')
    revision = 2 if name == 'xscreensaver' else 1
    changelog = f'''{name} ({version}+stereo3d{revision}) testing; urgency=medium

  * Add the reviewed stereo show integration for Sparky Stereo OS.
  * Preserve Debian's build configuration and add the stereo dependencies.

 -- {maintainer}  Tue, 13 Oct 2026 00:00:00 -0300

'''
    if name == 'xscreensaver':
        changelog = changelog.replace(
            '  * Add the reviewed stereo show integration for Sparky Stereo OS.',
            '  * Retain the native side-by-side Rocks mode and original settings.\n'
            '  * Expose Flurry particle depths through its existing OpenGL camera.\n'
            '  * Clean regenerated driver files and use the images double-colon rule.')
    (debian/'changelog').write_text(changelog+(debian/'changelog').read_text())
    patchtext = (repo/patch).read_text()
    if name == 'xscreensaver':
        for source, target in [('savers/saver-x11-frame.h','hacks/saver-x11-frame.h'), ('savers/x11-frame.c','hacks/x11-frame.c')]:
            lines = (repo/source).read_text().splitlines(True)
            patchtext += ''.join(difflib.unified_diff([], lines, fromfile='/dev/null', tofile='b/'+target))
        makefile = tree/'hacks/Makefile.in'
        old = makefile.read_text()
        before = 'rocks:\t\trocks.o\t\t$(HACK_OBJS) $(COL)\n\t$(CC_HACK) -o $@ $@.o\t$(HACK_OBJS) $(COL) $(HACK_LIBS)'
        after = '''rocks.o: CPPFLAGS += $(shell pkg-config --cflags stereo-declare)
rocks:\t\trocks.o x11-frame.o $(HACK_OBJS) $(COL)
\t$(CC_HACK) -o $@ $@.o x11-frame.o $(HACK_OBJS) $(COL) $(HACK_LIBS) $(shell pkg-config --libs stereo-declare)'''
        assert before in old
        new = old.replace(before, after)
        patchtext += ''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='a/hacks/Makefile.in', tofile='b/hacks/Makefile.in'))
        with (debian/'copyright').open('a') as out:
            out.write('\nFiles: hacks/x11-frame.c hacks/saver-x11-frame.h debian/patches/stereo-show.patch\nCopyright: 2026 Daniel Ramos\nLicense: GPL-2+\n\nLicense: GPL-2+\n This program is free software; you can redistribute it and/or modify it\n under the GNU General Public License, version 2 or any later version.\n On Debian systems see /usr/share/common-licenses/GPL-2.\n')
    patches = debian/'patches'
    patches.mkdir(exist_ok=True)
    filename = 'stereo-show.patch'
    (patches/filename).write_text('Description: Reviewed stereo show integration\nAuthor: Daniel Ramos <Capitain_Jack@yahoo.com>\nForwarded: not-needed\nLast-Update: 2026-10-13\n\n'+patchtext)
    with (patches/'series').open('a') as out:
        out.write('\n'+filename+'\n')
    if name == 'xscreensaver':
        rebuild_patch=patches/'92_hacks_images_distclean.patch'
        rebuild_patch.write_text(rebuild_patch.read_text().replace('+distclean: clean','+distclean:: clean'))
        with (debian/'clean').open('a') as out:
            out.write('\ndriver/demo-Gtk-resources.c\ndriver/xscreensaver-settings.desktop\ndriver/xscreensaver.desktop\ndriver/xscreensaver.service\n')
        (patches/'flurry-gl-camera.patch').write_text((repo/'savers/flurry-gl-camera.patch').read_text())
        with (patches/'series').open('a') as out: out.write('flurry-gl-camera.patch\n')
        with copyright_file.open('a') as out: out.write('\n'+(repo/'packaging/xscreensaver-flurry.copyright').read_text())
    subprocess.run(['dpkg-source','--before-build',str(tree)], check=True)
