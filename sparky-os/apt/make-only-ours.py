#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/07
# Copyright 2026 under the GNU GPL3 License
# Writes apt/sparky-stereo-only-ours: Debian's and deb-multimedia's builds of every package the
# Sparky Stereo OS repository ships are blocked, so only ours are candidates and the others are
# never listed (Daniel, 2026-10-07: "block the correspondent packages and tasks from debian as
# well - they shall not be listed"), the rule Bino already followed. Debian's task-* and the
# multimedia blend's packages are blocked too: the role tasks are task-sparky-*.
# Packages the repository carries that are not ours are listed in NOT_OURS below, each with its reason: their own
# archive's builds are never blocked, and ours ranks under them (see NOT_OURS).
# FFmpeg and mpv are in it since our builds on deb-multimedia's source packages replaced the
# Debian-based ones (Daniel: "we should patch multimedia-deb ffmpeg, not debian's"), so
# deb-multimedia's own ffmpeg and mpv never install on the edition: the stereo patches are in ours.
# Each name carries the architectures the repository ships it for (krdc:amd64 krdc:arm64), so a name we
# ship for some architectures leaves Debian's other architectures of it free: apt_preferences(5), apt 3.3.3,
# "By default, only packages of the native architecture are matched. To match binary packages of any
# architecture, add the :any suffix to the package name. You can also limit matching to a specific
# architecture by appending the architecture name to the package name, separated by a colon character."
# A plain name meant "the native architecture", so on arm64 it blocked Debian's arm64 kio6 while we ship kio6
# for amd64 only, and on amd64 it never blocked Debian's i386 builds of what we ship for i386 (ORDER 318).
# apt files an Architecture: all package under the native architecture (measured with apt 3.3.3: on amd64
# "libkscreen-data:amd64" matches it, on arm64 it does not), so a name of Architecture: all carries the
# architectures we ship the rest of its source for: Debian's arm64 libkf6screen8 needs Debian's libkscreen-data
# at its exact version, and a plain libkscreen-data blocked that on arm64 too. It stays plain only when we ship
# no architecture-specific package of its source: then ours serves every architecture.
# On the repository's other architectures our build of such a package is not the candidate either (100, under
# Debian's 500): apt 3.3.3 does not take a version other than the candidate to satisfy Debian's arm64
# libkf6screen8, "Depends libkscreen-data (= 4:6.7.4-1) ... libkscreen-data:arm64=4:6.7.4-1 is not selected".
# A program or library we ship for amd64 and not for i386 has its Debian and deb-multimedia i386 builds blocked too, so apt
# never lists them (Daniel, 2026-11-01: "32 bit builds we need? why are you even asking if we have 64 bit versions?";
# ORDER 321b). They could never be installed beside ours: a Multi-Arch: same library must be at the same version on every
# architecture, a program of the other architecture replaces ours, and 29 of them, of 17 sources (dolphin:i386, the KDE
# libraries' i386 builds), need Debian's Architecture: all -data package at its exact version, which ours replaces
# (ORDER 321's check). The i386 packages that stay are the libraries Steam, 32-bit Wine and 32-bit games need, and ours
# where we replace them (Mesa, FFmpeg, SDL 3, wine32, dxvk-wine32 and the rest we ship for i386): steam-installer, wine32,
# dxvk-wine32 and lutris pull 320 i386 packages, none of them a name we ship for amd64 only (measured on 1 Nov 2026).
# An Architecture: all name keeps the architectures of its source: apt files it under the native architecture, so an i386
# qualifier would match it on i386 machines only. I386_FROM_UPSTREAM names a library we ship for amd64 only whose i386 build Steam, Wine or a 32-bit game needs from Debian or
# deb-multimedia, with the reason; such a name keeps its i386 build free.
# Usage: make-only-ours.py [repository ...]   (default SPARKY_REPO_DIR of the local configuration); rerun when the
# repository gains packages, then rebuild sparky-stereo-apt. Each argument is a flat repository (its Packages),
# a published tree (its dists/*/main/binary-*/Packages) or a Packages file; the names of all of them are blocked.
import glob, os, sys
if len(sys.argv) > 1:
    repos = sys.argv[1:]
else:
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'config'))
    import local_config
    repos = [local_config.get('SPARKY_REPO_DIR')]
PENDING_DMO = set()          # source packages still on their way to dmo's packaging (none: ffmpeg and mpv are on it now)
# Packages the repository carries but that are not ours: another archive's package, only repackaged or rebuilt through
# Lean Code (its version is the other archive's plus +lc1), which that archive must keep updating. Their builds in Debian and
# deb-multimedia are not blocked, and ours ranks at 400, under the 500 of an archive with no pin (apt_preferences(5): "100 <=
# P < 500 causes a version to be installed unless there is a version available belonging to some other distribution or the
# installed version is more recent"), so the other archive's newer version wins and ours is only the way in. Until
# ORDER 321 the rule was the pool path carried/; the published tree has no carried/ folder any more, so deb-multimedia's own
# keyring was blocked (ORDER 318's finding). Every other name the generator blocks is a build of ours (a +stereo3dN or
# +sparkyN version, or a package of ours with no build in either archive): ORDER 321 checked each against Debian forky and
# deb-multimedia forky.
I386_FROM_UPSTREAM = {}       # none on 1 Nov 2026
NOT_OURS = {
    'deb-multimedia-keyring': "deb-multimedia's own keyring, 2024.9.1 in deb-multimedia (2024.9.1+lc1 here). The repository carries "
                              "it so that sparky-stereo-apt can depend on it before deb-multimedia is in the sources; when deb-multimedia "
                              "rotates its key, its new keyring package must reach the edition, or the edition's deb-multimedia source breaks.",
    'libunibreak7': "Debian's libunibreak 7.0-2, rebuilt only through Lean Code, carried when Debian testing moved to libunibreak8 on 2026-10-16 while deb-multimedia's "
                    "libass9 still needed libunibreak7; Debian's source is at 8.0-2 now (and deb-multimedia's libass9 2:0.17.5-dmo3 needs "
                    "libunibreak8).",
    'libunibreak7-dbgsym': "the debug symbols of the carried libunibreak7 (Debian's are in its debug archive).",
    'libunibreak-dev': "Debian's libunibreak 7.0-2, as libunibreak7; Debian's libunibreak-dev 8.0-2 must not be blocked or outranked.",
    'libunibreak-doc': "Debian's libunibreak 7.0-2, as libunibreak7; Debian's libunibreak-doc 8.0-2 must not be blocked or outranked.",
}


def indexes(repo):
    if os.path.isfile(repo):
        return [repo]
    if os.path.isfile(os.path.join(repo, 'Packages')):
        return [os.path.join(repo, 'Packages')]
    found = sorted(glob.glob(os.path.join(repo, 'dists', '*', '*', 'binary-*', 'Packages')))
    if not found:
        sys.exit('make-only-ours.py: no Packages index in ' + repo)
    return found


arches, source, built, not_ours = {}, {}, {}, set()
for path in (p for repo in repos for p in indexes(repo)):
    for st in open(path, errors='replace').read().split('\n\n'):
        f = dict(l.split(': ', 1) for l in st.split('\n') if ': ' in l and not l.startswith(' '))
        if not f.get('Package'):
            continue
        src = f.get('Source', f['Package']).split()[0]
        if src in PENDING_DMO or f['Package'].startswith(('sparky-stereo', 'task-sparky-')):
            continue
        if f['Package'] in NOT_OURS:
            not_ours.add(f['Package'])
            continue
        arch = f.get('Architecture', 'all')
        arches.setdefault(f['Package'], set()).add(arch)
        source.setdefault(f['Package'], src)
        if arch != 'all':
            built.setdefault(src, set()).add(arch)
tree_arches = set().union(*built.values()) if built else set()
specs, elsewhere, i386_only_upstream = [], [], 0
for name in sorted(arches):
    qualified = arches[name] - {'all'}
    if 'all' in arches[name]:
        if built.get(source[name]):
            qualified |= built[source[name]]
            elsewhere += [name + ':' + arch for arch in sorted(tree_arches - built[source[name]])]
        else:
            specs.append(name)
    if 'all' not in arches[name] and 'amd64' in qualified and 'i386' not in qualified and name not in I386_FROM_UPSTREAM:
        qualified.add('i386')
        i386_only_upstream += 1
    specs += [name + ':' + arch for arch in sorted(qualified)]
out = ['# Generated by apt/make-only-ours.py from the repository index; do not edit by hand.',
       '# Only Sparky Stereo OS builds of these packages are candidates.',
       '# Each name carries the architectures we ship it for (an Architecture: all package those of its source);',
       '# a plain name is an Architecture: all package whose source we ship for no architecture in particular.',
       '# A name we ship for amd64 and not for i386 is blocked for i386 too: the edition builds nothing new for i386.', '']
for origin in ('Debian', 'Unofficial Multimedia Packages'):
    out += ['Package: ' + ' '.join(specs), 'Pin: release o=' + origin, 'Pin-Priority: -1', '']
if elsewhere:
    out += ['# Our Architecture: all builds of a source we ship for some architectures only, on the others: Debian\'s packages',
            '# of that source need Debian\'s build at its exact version there, so ours is not the candidate',
            'Package: ' + ' '.join(elsewhere), 'Pin: release o=Sparky Stereo OS', 'Pin-Priority: 100', '']
if not_ours:
    out += ['# Packages the repository carries that are not ours (NOT_OURS in apt/make-only-ours.py): another archive\'s package,',
            '# only repackaged or rebuilt through Lean Code, which that archive keeps updating. Its builds are not blocked, and ours ranks',
            '# under them, so the newer one from that archive wins; ours is only the way in.']
    out += ['#   %s: %s' % (name, NOT_OURS[name]) for name in sorted(not_ours)]
    out += ['Package: ' + ' '.join(name + ':any' for name in sorted(not_ours)), 'Pin: release o=Sparky Stereo OS', 'Pin-Priority: 400', '']
out += ['# Debian\'s tasks and the multimedia blend: the edition\'s tasks are task-sparky-*', 'Package: task-* multimedia-*',
        'Pin: release o=Debian', 'Pin-Priority: -1', '']
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'sparky-stereo-only-ours'), 'w').write('\n'.join(out))
print(len(arches), 'packages blocked from Debian and deb-multimedia, as', len(specs), 'architecture-qualified names;',
      len(elsewhere), 'Architecture: all names of ours at 100 on the architectures their source is not built for;',
      len(not_ours), 'packages that are not ours at 400;', i386_only_upstream, 'names we ship for amd64 only, blocked for i386 too')
for name in sorted(set(NOT_OURS) - not_ours):
    print('make-only-ours.py: NOT_OURS lists %s, which no index carries any more: remove it from the list' % name, file=sys.stderr)
