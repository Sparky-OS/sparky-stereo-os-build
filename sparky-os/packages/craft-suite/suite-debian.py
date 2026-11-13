#!/usr/bin/env python3
# Sparky Stereo OS: writes the generated part of the Craft suite's debian/ folder: control, changelog, copyright, the
# libraries' names, the version choices file and the files each package installs.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/13
"""suite-debian.py SOURCE WORKSPACE VERSION RFC2822_DATE RUSTC_VERSION STD_PACKAGE [APP...]
    SOURCE: the unpacked source (apps/, vendor/, fonts/, i18n/, debian/ with this recipe's files and
    debian/authors/APP.txt); WORKSPACE: the workspace suite-generate.sh made from it with the build's compiler (the
    libraries' names are read there); VERSION: the source version; RUSTC_VERSION: the rustc package version the
    names were made with; STD_PACKAGE: the runtime package of that compiler's standard library."""
import json
import re
import sys
import textwrap
import tomllib
from pathlib import Path

MAINTAINER = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
CREDIT = ('Sparky Stereo OS, Daniel Ramos\'s (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, '
          'by Paweł "pavroo" Pijanowski)')
CREDIT_LINES = ('Sparky Stereo OS, Daniel Ramos\'s (Capitain Jack) edition of SparkyLinux\n'
                ' (https://sparkylinux.org, by Paweł "pavroo" Pijanowski)')
# Libraries the programs open at run time (winit, wgpu, the file dialogs), which no ELF header names; upstream's own
# package lists the same ones.
RUNTIME = ('libxkbcommon0, libxkbcommon-x11-0, libwayland-client0, libwayland-cursor0, libwayland-egl1, libx11-6, '
           'libx11-xcb1, libxcb1, libxcursor1, libxi6, libxrandr2, libvulkan1 | libegl1')
DESCRIPTIONS = {
    'photocraft': ('graphics', 'native image editor with layers, masks and PSD files (stereo edition)',
                   ['Layers, masks, adjustment layers, layer styles, type and brushes; opens and saves layered',
                    'PSD and PSB files; 8, 16 and 32-bit documents; GPU compositing.',
                    'Includes photocraft-cli, a headless converter and command runner.']),
    'lightcraft': ('graphics', 'native photo library and raw developer (stereo edition)',
                   ['A photo library with non-destructive development of raw and ordinary photos, and export.',
                    'Includes lightcraft-cli, a headless command runner.']),
    'filmcraft': ('video', 'native video editor: edit video, colour and sound (stereo edition)',
                  ['Timeline editing with source and program monitors, colour grading and scopes, effects and',
                   'keyframes, titles and captions, audio mixing and export.',
                   'Includes filmcraft-cli, a headless command runner and exporter.']),
    'anicraft': ('graphics', 'native 2D vector animation editor (stereo edition)',
                 ['Vector drawing on a timeline with symbols, a stage camera and layer depth, and a movie player.',
                  'Includes anicraft-cli, a headless command runner.']),
    'texturecraft': ('graphics', 'native 3D texture painting editor (stereo edition)',
                     ['Paints textures on a 3D model, with layers, baking and flat UV views.',
                      'Includes texturecraft-cli, a headless command runner.']),
}
STEREO = {
    'photocraft': 'Stereo pictures (MPO, JPS, PNG with sTER) open as a pair in a Stereo View window.',
    'lightcraft': 'Stereo photos (HEIF and PNG pairs) open as a pair in a Stereo View window.',
    'filmcraft': 'Stereo video and stills play as a pair in a Stereo Monitor window.',
    'anicraft': 'The movie stage is drawn once per eye, each layer shifted by its depth, in a Stereo View window.',
    'texturecraft': 'The model is drawn by two cameras in a Stereo View window.',
}


def crate_rows(vendor):
    rows = []
    for man in sorted(vendor.glob('registry/*/Cargo.toml')) + sorted(vendor.glob('git/*/*/Cargo.toml')):
        pkg = tomllib.loads(man.read_text())['package']
        where = man.parent.parent.name if man.parent.parent.parent.name == 'git' else 'crates.io'
        lic = pkg.get('license') or ('see ' + pkg['license-file'] if pkg.get('license-file') else 'see the crate')
        authors = [re.sub(r'\s*<[^>]*>', '', a).strip() for a in pkg.get('authors', [])]
        rows.append((lic, pkg['name'], pkg['version'], where, [a for a in authors if a]))
    return rows


def wrap(prefix, words, width=78):
    lines, line = [], prefix
    for w in words:
        if len(line) + len(w) + 1 > width and line.strip():
            lines.append(line.rstrip())
            line = ' ' + w
        else:
            line += ('' if line.endswith(' ') or not line else ' ') + w
    lines.append(line.rstrip())
    return lines


def main():
    src, ws, version, date, rustc, std = (Path(sys.argv[1]), Path(sys.argv[2]), *sys.argv[3:7])
    suite = json.loads((src / 'debian/suite.json').read_text())
    apps = sys.argv[7:] or list(suite['build'])
    deb = src / 'debian'
    sonames = {'craft-suite': (ws / 'shared/soname.txt').read_text().strip()}
    for a in apps:
        sonames[a] = (ws / f'{a}-shared/soname.txt').read_text().strip()
    libpkg = sonames['craft-suite'].removeprefix('lib').removesuffix('.so')
    libpkg = 'lib' + libpkg
    (deb / 'suite-sonames.txt').write_text(''.join(f'{k} {v}\n' for k, v in sorted(sonames.items())) + f'rustc {rustc}\n')
    (deb / 'suite-apps.txt').write_text(''.join(a + '\n' for a in apps))

    control = [f'''Source: craft-suite
Section: graphics
Priority: optional
Maintainer: {MAINTAINER}
Build-Depends: debhelper-compat (= 13), rustc (= {rustc}), cargo (= {rustc}), libstd-rust-dev (= {rustc}),
 pkgconf, cmake, nasm, patch, python3, desktop-file-utils, appstream,
 libxkbcommon-dev, libwayland-dev, libx11-dev, libxrandr-dev, libxi-dev, libgl-dev, libgtk-3-dev, libasound2-dev,
 libfontconfig-dev, libfreetype-dev, libudev-dev, libssl-dev, libheif-dev
Standards-Version: 4.7.4
Rules-Requires-Root: no
Homepage: https://sparkylinux.org
Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues

Package: craft-suite-common
Architecture: all
Multi-Arch: foreign
Depends: ${{misc:Depends}}
Description: Craft suite: what the edition's packages of the apps share as data
 The version choices file that tells each Craft app its updates come from the
 package manager: with it an app's own update check offers nothing and asks
 no server.
 .
 {CREDIT_LINES}.

Package: {libpkg}
Architecture: amd64
Multi-Arch: same
Section: libs
Depends: ${{shlibs:Depends}}, ${{misc:Depends}}
Description: Craft suite: the Rust crates the apps have in common, as one shared library
 The crates two or more Craft apps link, built once as a Rust dynamic library.
 The library's name carries the compiler and every crate, version, source and
 feature in it, so each app depends on exactly the library it was built with.
 .
 {CREDIT_LINES}.
''']
    for a in apps:
        section, short, long = DESCRIPTIONS[a]
        app = suite['apps'][a]
        control.append(f'''
Package: {a}
Architecture: amd64
Section: {section}
Depends: ${{shlibs:Depends}}, ${{misc:Depends}}, craft-suite-common (= ${{source:Version}}), {RUNTIME}
Recommends: mesa-vulkan-drivers, libegl-mesa0, xdg-desktop-portal
Description: {short}
''' + ''.join(f' {line}\n' for line in textwrap.wrap(' '.join(long) + ' ' + STEREO[a], 76)) + f''' .
 {a} {app['version']}, built from the edition's stereo branch
 {app['branch']} at {app['rev'][:12]}, with the suite's shared libraries.
 .
 {CREDIT_LINES}.
''')
    (deb / 'control').write_text(''.join(control))

    lines = '\n'.join(f'  * {a} {suite["apps"][a]["version"]} from {suite["apps"][a]["branch"]} at {suite["apps"][a]["rev"][:12]}.' for a in apps)
    (deb / 'changelog').write_text(f'''craft-suite ({version}) mashtabba; urgency=medium

  * The Craft suite as one source package: every app a package of its own, the
    crates the apps share in {libpkg}, each app's own crates in
    one library inside its package, built by the edition's rustc {rustc}
    from vendored crates with no network.
{lines}
  * An app's own update check offers nothing in a packaged install
    (craft-suite-common's version choices file); apt updates the packages.

 -- {MAINTAINER}  {date}
''')

    versions = {'apps': {a: {'Pinned': suite['apps'][a]['version']} for a in apps}}
    (deb / 'versions.json').write_text(json.dumps(versions, indent=1, sort_keys=True) + '\n')
    (deb / 'craft-suite-common.install').write_text('debian/versions.json usr/share/craft-suite\n')
    (deb / 'suite-libpkg.txt').write_text(libpkg + '\n')
    # copyright
    c = [f'''Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Craft suite (PhotoCraft, LightCraft, FilmCraft, AniCraft, TextureCraft, craft-libs)
Upstream-Contact: Storytold (https://github.com/storytold)
Source: https://github.com/storytold, built from the stereo edition branches on https://github.com/danielcamposramos
Comment: The revisions are in debian/suite.json. Everyone the commits of each repository name as an author is
 listed in debian/authors/ and installed as /usr/share/doc/<app>/AUTHORS.
''']
    names = {'photocraft': 'PhotoCraft', 'lightcraft': 'LightCraft', 'filmcraft': 'FilmCraft', 'anicraft': 'AniCraft',
             'texturecraft': 'TextureCraft'}
    for a in apps:
        notice = (src / 'apps' / a / 'NOTICE')
        holder = f'ArtCraft Team and the {names[a]} contributors'
        if notice.exists():
            m = re.search(r'^Copyright \(c\) (.*?)\.?$', notice.read_text(), re.M)
            holder = m[1] if m else holder
        c.append(f'''Files: apps/{a}/*
Copyright: {holder}
License: MIT or Apache-2.0
Comment: The stereo work on the edition branch is by Daniel Campos Ramos with the AI partners named in the commits'
 Assisted-by trailers; carried fixes keep their authors (Dylan M. Taylor, Mitch Lindgren and the others the
 commits name). Third-party material inside the app is listed in apps/{a}/NOTICE and apps/{a}/ATTRIBUTION.md.
''')
    c.append('''Files: fonts/*
Copyright: the authors of each font family, named in the family's OFL.txt and in fonts/*/fonts/manifest.txt
License: OFL-1.1
Comment: storytold/craft-fonts; the manifest, tools and documentation of that repository are
 Copyright ArtCraft Team and the craft-fonts contributors, MIT or Apache-2.0.

Files: i18n/*
Copyright: ArtCraft Team and the craft-i18n contributors; translators by locale in i18n/*/ATTRIBUTION.md
License: MIT or Apache-2.0
''')
    by_lic = {}
    for lic, name, ver, where, authors in crate_rows(src / 'vendor'):
        by_lic.setdefault(lic, []).append((name, ver, where, authors))
    for lic in sorted(by_lic):
        rows = by_lic[lic]
        crates = sorted({f'{n} {v}' + ('' if w == 'crates.io' else f' ({w})') for n, v, w, _ in rows})
        # names that differ only in case sort by their own bytes next: a set's order is not the same in two runs
        people = sorted({a for *_, au in rows for a in au}, key=lambda a: (a.casefold(), a))
        c.append('Files: vendor/*\n' + '\n'.join(wrap('Copyright: ', people or ['the authors named in each crate'])) + f'\nLicense: {lic}\n'
                 + '\n'.join(wrap('Comment: ' + f'{len(crates)} crates under this licence expression, authors as each crate\'s Cargo.toml names them: ', [x + ',' for x in crates[:-1]] + crates[-1:])) + '\n')
    c.append(f'''Files: debian/*
Copyright: 2026 Daniel Ramos (Capitain Jack)
License: GPL-3+
Comment: {CREDIT_LINES}.
 The packaging is by Daniel Ramos with Claude Fable 5.2 (Anthropic) assisting.

License: MIT or Apache-2.0
 Either licence may be used; the full texts are in each app's LICENSE-MIT and LICENSE-APACHE, installed in
 /usr/share/doc/<app>/, and in /usr/share/common-licenses/Apache-2.0.

License: OFL-1.1
 The SIL Open Font License, version 1.1; each family's text is in fonts/*/fonts/<family>/OFL.txt and is installed
 as /usr/share/doc/<app>/OFL-<family>.txt.

License: GPL-3+
 On Debian systems the full text of the GNU General Public License version 3 is in
 /usr/share/common-licenses/GPL-3.
''')
    (deb / 'copyright').write_text('\n'.join(c))
    print(f'{libpkg}; {len(apps)} apps; {sum(len(v) for v in by_lic.values())} vendored crates in {len(by_lic)} licence expressions')


if __name__ == '__main__':
    if len(sys.argv) < 7:
        sys.exit(__doc__)
    main()
