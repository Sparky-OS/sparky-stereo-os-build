#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/02
# Copyright 2026 under the GNU GPL3 License
# Writes DEBIAN/control for the edition's meta-packages from the package lists, so the
# lists stay the one source. Usage: make-meta.py <version> <out-dir>
#   <out-dir>/<package>/DEBIAN/control  (Installed-Size from <out-dir>/<package>, if it exists)
# Policy: the system essentials and our stereo stack go in Depends, applications, games and
# optional tools in Recommends, so a user can remove an application and keep the meta-package.
# Never listed: hardware-found.list (the hardware setup installs those per machine), aptus.list
# and base-remove.list (not installed), and emulation-3d.list (emulators install from APTus
# Stereo AppCenter, never from the ISO; prepack.sh --final purges them).
# Last update 2026/10/07: role tasks task-sparky-stereo-<role> (and task-sparky-<role> for the
# 2D programs of science and education), sparky-stereo-gaming transitional, sparky-stereo-tasks for tasksel
import os, re, subprocess, sys

REPO = os.environ.get('REPO', '/K3D/temp/sparky-os/repo')

def repo_versions():
    # highest version of every package in the repository's Packages index
    ver = {}
    for para in open(os.path.join(REPO, 'Packages'), errors='replace').read().split('\n\n'):
        f = dict(l.split(': ', 1) for l in para.split('\n') if ': ' in l and not l.startswith(' '))
        n, v = f.get('Package'), f.get('Version')
        if n and (n not in ver or subprocess.run(['dpkg', '--compare-versions', v, 'gt', ver[n]]).returncode == 0):
            ver[n] = v
    return ver

RV = repo_versions()

KERNEL = next(n for n in RV if re.fullmatch(r'linux-image-[0-9.]+-rc[0-9]+-stereo3d|linux-image-[0-9.]+-stereo3d', n))
KREL = KERNEL[len('linux-image-'):]
# kernel meta-packages: versioned after the kernel package (7.3.0-rc1-stereo3d, build 3)
KVERSION = KREL.replace('-rc', '~rc').replace('-stereo3d', '') + '+stereo3d' + RV[KERNEL]

HERE = os.path.dirname(os.path.abspath(__file__))
MAINT = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'

def lst(name):
    return [l.strip() for l in open(os.path.join(HERE, name + '.list'))
            if l.strip() and not l.startswith('#')]

# Packages of ours (sparky-os/repo) the lists do not carry, because apt did not offer them
# when make-lists.py ran.
OURS_HARDWARE = ['pipewire-bluez5-codec-aac']

# The edition's video player, VLC Stereo (installed beside the distribution's VLC; its PipeWire
# output is a package of its own), and the audio output that goes with it.
OURS_PLAYER = ['vlc-stereo']
OURS_PLAYER_OUTPUT = ['vlc-stereo-plugin-pipewire']

# Optional inside an otherwise essential list.
HARDWARE_OPTIONAL = {'libfdk-aac2', 'displaylink-driver', 'evdi-dkms', 'hw-probe', 'memtest86+', 'inxi'}
SYSTEM_OPTIONAL = {'distrobox', 'timeshift', 'waydroid'}

# The edition's core (Daniel's call): our kernel, our KDE stack and our Mesa at the repository's
# versions, with the Vulkan stereo layer (shipped and on by default, Daniel 2026-10-04); the
# dependencies of these follow. NVIDIA is never listed (the hardware setup installs it; our
# libnvidia-egl-wayland1 wins by the repository pin when the driver pulls it in).
STEREO_STACK = ['linux-image-sparky-stereo', 'linux-headers-sparky-stereo'] + [
    f'{n} (>= {RV[n]})' for n in ('kscreen', 'kwin-wayland', 'libkscreen-bin',
                                  # Mesa's GLX, EGL and GBM libraries depend on mesa-libgallium
                                  # at their exact version, so naming it keeps them ours too
                                  'mesa-libgallium', 'mesa-vulkan-drivers', 'mesa-vulkan-layer-stereo')]

# Role tasks (Daniel, 2026-10-07): task-sparky-stereo-<role> for every role; scientist and
# student also get task-sparky-<role> with their programs that have no stereo yet, so people
# can install those without touching our stereo builds (roles.tsv, third column).
ROLES = {
    'gamer': ('gamer', 'games, Steam, the stereo Lutris build, the game runtimes and the controllers'),
    'designer': ('designer', 'drawing, painting, photo and 3D modelling programs, colour management'),
    'creator': ('video creator', 'video editing, streaming, encoding and subtitling'),
    'musician': ('musician', 'audio production: plugins, synthesizers, routing and recording'),
    'scientist': ('scientist', 'science and engineering: mathematics, chemistry, maps, CAD, GIS and plotting'),
    'student': ('student', 'education: the KDE Edu programs and GCompris'),
    'simmer': ('simulator pilot and driver', 'flight and racing simulators and the tools for their rigs'),
    'maker': ('maker', '3D printing: modelling, mesh checking and repair, slicing, printer control, 3D scanning and electronics'),
    'engineer': ('electrical and automation engineer', 'circuits and PCBs, electrical diagrams, circuit simulation, logic analysers and serial tools, FPGAs, PLC programming, SCADA and HMI, industrial protocols and power systems'),
}
SPLIT = {'scientist', 'student'}

def read_roles():
    by = {r: {'3d': set(), '2d': set()} for r in ROLES}
    for l in open(os.path.join(HERE, 'roles.tsv')):
        if not l.strip() or l.startswith('#'):
            continue
        c = l.rstrip('\n').split('\t')
        for r in c[1].split(','):
            by[r][c[2] if len(c) > 2 and c[2] else '3d'].add(c[0])
    return by

def available(pkgs):
    # in our repository, or known to apt (the lists already check theirs)
    out = subprocess.run(['apt-cache', 'show', '--no-all-versions'] + sorted(pkgs), capture_output=True, text=True).stdout
    known = set(re.findall(r'^Package: (\S+)', out, re.M)) | set(RV)
    missing = sorted(set(pkgs) - known)
    if missing:
        print('not in apt or our repository, left out:', ' '.join(missing), file=sys.stderr)
    return [p for p in pkgs if p in known]

RB = read_roles()
ROLED = set().union(*[RB[r]['3d'] | RB[r]['2d'] for r in RB])
GAMING_LISTS = sorted(set(lst('runtimes')) - {'ffmpeg', 'libvulkan1', 'python3'}) + lst('gaming') + lst('games')

def tasks():
    t = {}
    for r, (who, what) in ROLES.items():
        stereo = sorted(RB[r]['3d'] | (RB[r]['2d'] if r not in SPLIT else set()))
        dep = ['sparky-stereo-desktop']
        rec = available(stereo)
        if r == 'gamer':
            dep += ['ffmpeg', 'libvulkan1', 'python3']
            rec = sorted(set(rec) | set(GAMING_LISTS))
        t['task-sparky-stereo-' + r] = (
            'Sparky Stereo OS: ' + who,
            f'This task package installs the {who} programs of Sparky Stereo OS: {what}.'
            + (' Only the programs that show stereo 3D on Sparky Stereo OS today; task-sparky-' + r
               + ' installs the others.' if r in SPLIT else ''),
            dep, rec)
        if r in SPLIT:
            t['task-sparky-' + r] = (
                'SparkyOS: ' + who + ' (2D programs)',
                f'This task package installs the {who} programs of SparkyOS that have no stereo 3D version'
                f' yet: {what}. Install it together with task-sparky-stereo-{r}; it never replaces our'
                ' stereo builds.',
                ['sparky-stereo-desktop'], available(sorted(RB[r]['2d'])))
    return t

# name: (title line, body, depends, recommends)
META = {
    'sparky-stereo-desktop': (
        'Sparky Stereo desktop',
        'This meta package installs the desktop of Sparky Stereo OS: the look, console and system information of the edition, time synchronisation, the Dolphin menu that converts audio files, VLC Stereo as the video player, and the applications beyond the KDE edition.',
        ['sparky-stereo-audio-convert', 'sparky-stereo-console', 'sparky-stereo-info', 'sparky-stereo-look', 'sparky-stereo-time'] + lst('look') + OURS_PLAYER,
        [p for p in lst('apps') if p not in ROLED] + OURS_PLAYER_OUTPUT),
    'sparky-stereo-gaming': (
        'Sparky Stereo gaming (transitional package)',
        'This transitional package moves systems to task-sparky-stereo-gamer, the gamer task of Sparky Stereo OS. It can be removed.',
        ['task-sparky-stereo-gamer'], []),
    'sparky-stereo-languages': (
        'Sparky Stereo languages',
        'This meta package installs the languages of Steam for the applications Sparky Stereo OS ships: dictionaries, hyphenation, fonts, help and input methods.',
        [],
        lst('languages')),
    'sparky-stereo-hardware-support': (
        'Sparky Stereo hardware support',
        'This meta package installs the firmware, microcode, video acceleration and the tools the hardware setup of Sparky Stereo OS uses. The NVIDIA driver is not included: the hardware setup installs it when it finds the card.',
        sorted(set(lst('hardware')) - HARDWARE_OPTIONAL - {'libfdk-aac2'}) + OURS_HARDWARE,
        sorted(HARDWARE_OPTIONAL & set(lst('hardware')))),
    'sparky-stereo-system': (
        'Sparky Stereo system',
        'This meta package installs the system tools of Sparky Stereo OS: Flatpak, snapshots, containers, Android support and zram.',
        sorted(set(lst('system')) - SYSTEM_OPTIONAL) + STEREO_STACK,
        sorted(SYSTEM_OPTIONAL & set(lst('system')))),
    'linux-image-sparky-stereo': (
        'Sparky Stereo kernel',
        'This meta package installs the current stereo 3D kernel of Sparky Stereo OS.',
        [f'{KERNEL} (>= {RV[KERNEL]})'], []),
    'linux-headers-sparky-stereo': (
        'Sparky Stereo kernel headers',
        'This meta package installs the headers of the current stereo 3D kernel of Sparky Stereo OS, for DKMS modules.',
        ['linux-headers-' + KREL + f' (>= {RV["linux-headers-" + KREL]})', 'linux-image-sparky-stereo'], []),
    'sparky-stereo': (
        'Sparky Stereo OS',
        'This meta package installs Sparky Stereo OS, the stereo 3D edition of SparkyLinux: the desktop, gaming, languages, hardware support and system meta packages.',
        ['sparky-stereo-desktop', 'sparky-stereo-hardware-support',
         'sparky-stereo-languages', 'sparky-stereo-system'],
        ['sparky-stereo-tasks']),
}
META.update(tasks())
META['sparky-stereo'] = (META['sparky-stereo'][0], META['sparky-stereo'][1].replace('the desktop, gaming, languages, hardware support and system meta packages', 'the desktop, languages, hardware support and system meta packages, and every role task (gamer, designer, video creator, musician, scientist, student, simulator pilot and driver, maker, electrical and automation engineer)'), META['sparky-stereo'][2], META['sparky-stereo'][3] + sorted(k for k in META if k.startswith('task-')))
META['sparky-stereo-tasks'] = (
    'Sparky Stereo OS tasks for tasksel',
    'This package lists the role tasks of Sparky Stereo OS in tasksel, the Debian way: gamer, designer, video creator, musician, scientist, student, simulator pilot and driver, maker, electrical and automation engineer, with the 2D programs of science and education as their own tasks.',
    ['tasksel'], [])

def desc():
    out = ['Task: sparky-stereo', 'Relevance: 3', 'Key:', '  sparky-stereo-desktop', 'Section: user',
           'Description: Sparky Stereo OS', ' The stereo 3D edition of SparkyLinux, based on Debian.', '']
    for k in sorted(META):
        if not k.startswith('task-'):
            continue
        title, body = META[k][0], META[k][1]
        out += ['Task: ' + k[len('task-'):], 'Parent: sparky-stereo', 'Relevance: 5', 'Key:', '  ' + k,
                'Section: user', 'Description: ' + title, ' ' + body, '']
    return '\n'.join(out)

def main():
    if sys.argv[1:2] == ['--list']:
        print(' '.join(sorted(META)))
        return
    version, out = sys.argv[1:3]
    d = os.path.join(out, 'sparky-stereo-tasks', 'usr', 'share', 'tasksel', 'descs')
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'sparky-stereo.desc'), 'w').write(desc())
    # Debian's own task lists step aside (Daniel, 2026-10-07: "block the correspondent packages and
    # tasks from debian as well - they shall not be listed"): tasksel reads only *.desc files, so
    # a diversion to another name hides them; isenkram's hardware tasks stay.
    hidden = ['debian-tasks.desc', 'debian-multimedia-tasks.desc']
    dd = os.path.join(out, 'sparky-stereo-tasks', 'DEBIAN'); os.makedirs(dd, exist_ok=True)
    pre = ['#!/bin/sh', 'set -e', 'if [ "$1" = install ] || [ "$1" = upgrade ]; then']
    post = ['#!/bin/sh', 'set -e', 'if [ "$1" = remove ] || [ "$1" = purge ] || [ "$1" = abort-install ]; then']
    for h in hidden:
        f = '/usr/share/tasksel/descs/' + h
        pre.append(f'\tdpkg-divert --package sparky-stereo-tasks --rename --divert {f}.sparky-hidden --add {f}')
        post.append(f'\tdpkg-divert --package sparky-stereo-tasks --rename --remove {f}')
    for name, lines in (('preinst', pre + ['fi', '#DEBHELPER#'.replace('#DEBHELPER#', '')]), ('postrm', post + ['fi'])):
        path = os.path.join(dd, name)
        open(path, 'w').write('\n'.join(l for l in lines if l != '') + '\n'); os.chmod(path, 0o755)
    for pkg, (title, body, dep, rec) in META.items():
        dep = sorted(set(dep))
        for n in dep:   # no versioned library names in Depends
            b = n.split(' ')[0].split(':')[0]
            if re.match(r'lib.*(\d|t64)', b) and b not in ('libvulkan1', 'libkscreen-bin'):
                sys.exit(f'{pkg}: versioned library {n} in Depends')
        v = KVERSION if pkg.startswith('linux-') else version
        rec = sorted(set(rec) - set(dep))
        d = os.path.join(out, pkg)
        os.makedirs(os.path.join(d, 'DEBIAN'), exist_ok=True)
        size = subprocess.run(['du', '-sk', '--exclude=DEBIAN', d], capture_output=True, text=True).stdout.split()[0]
        f = [('Package', pkg), ('Version', v), ('Architecture', 'all'), ('Maintainer', MAINT),
             ('Installed-Size', size)]
        if dep:
            f.append(('Depends', ', '.join(dep)))
        if rec:
            f.append(('Recommends', ', '.join(rec)))
        f += [('Section', 'System'), ('Priority', 'optional'), ('Homepage', 'https://sparkylinux.org'),
              ('Description', title + '\n  ' + body)]
        with open(os.path.join(d, 'DEBIAN', 'control'), 'w') as c:
            c.write(''.join(f'{k}: {v}\n' for k, v in f))

main()
