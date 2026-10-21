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
# Last update 2026/10/19: both developer tasks remain opt-in; only the OS-developer task depends on
# sparky-stereo-skills, for distribution maintainers and their human/local/hosted partners.
# Earlier update 2026/10/14: each package gets its copyright file here (build.sh no longer writes it).
# Earlier update 2026/10/07: role tasks task-sparky-stereo-<role> (and task-sparky-<role> for the
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

def kernel_version(n):
    # the kernel meta-packages' version for a base-flavour image: build 6 was named
    # linux-image-7.3.0-rc1-stereo3d (version 6); from build 7 the build is in the name,
    # linux-image-7.3.0-rc6-stereo3d8 (version 7.3.0~rc6-8). Both give 7.3.0~rc6+stereo3d8.
    m = re.fullmatch(r'linux-image-([0-9.]+)(?:-(rc[0-9]+))?-stereo3d([0-9]*)', n)
    if not m:
        return None
    return m.group(1) + ('~' + m.group(2) if m.group(2) else '') + '+stereo3d' + (m.group(3) or RV[n])

def newer(a, b):
    return subprocess.run(['dpkg', '--compare-versions', a, 'gt', b]).returncode == 0

KERNEL = None
for n in RV:
    if kernel_version(n) and (KERNEL is None or newer(kernel_version(n), kernel_version(KERNEL))):
        KERNEL = n
KREL = KERNEL[len('linux-image-'):]
KVERSION = kernel_version(KERNEL)

def flavour_image(flavour):
    # the image of the same build in another flavour, when the repository has it: v3 is
    # linux-image-7.3.0-rc6-stereo3d8-v3, rt is linux-image-7.3.0-rc6-rt-stereo3d8
    m = re.fullmatch(r'linux-image-([0-9.]+(?:-rc[0-9]+)?)-stereo3d([0-9]*)', KERNEL)
    if not m:
        return None
    n = (f'linux-image-{m.group(1)}-stereo3d{m.group(2)}-v3' if flavour == 'v3'
         else f'linux-image-{m.group(1)}-rt-stereo3d{m.group(2)}')
    return n if n in RV and 'linux-headers-' + n[len('linux-image-'):] in RV else None

HERE = os.path.dirname(os.path.abspath(__file__))
# Every meta-package carries this copyright file, so a package is never empty and the
# md5sums of provenance.sh have files to sum.
COPYRIGHT = '''Sparky Stereo OS, Daniel Ramos's (Capitain Jack) edition of SparkyLinux (https://sparkylinux.org, by Paweł "pavroo" Pijanowski).

Upstream Author(s):
    Paweł "pavroo" Pijanowski <pavroo@onet.eu>
    Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>

Files: *
    Copyright (C) 2026 Paweł "pavroo" Pijanowski, Daniel Ramos (Capitain Jack)
    License: GPL-3

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
'''
MAINT = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'

def lst(name):
    return [l.strip() for l in open(os.path.join(HERE, name + '.list'))
            if l.strip() and not l.startswith('#')]

# Packages of ours (sparky-os/repo) the lists do not carry, because apt did not offer them
# when make-lists.py ran.
# sparky-stereo-hardware is the hardware setup itself and ships the GPU vendors' APT preferences
# (NVIDIA and AMD repositories); in Depends so every install, the ISO included, has the guards.
OURS_HARDWARE = ['pipewire-bluez5-codec-aac', 'sparky-stereo-hardware']

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
    'developer': ('developer', "KDE's development tools first (KDevelop, Kate and the KDE SDK, the Qt 6 and KDE Frameworks development files, Qt Creator), compilers, debuggers and build systems for C, C++, Rust, Go, Python, Java and the other languages Debian carries, version control, containers and virtual machines, graphics and GPU debugging, the game engines and game libraries"),
    'os-developer': ('Stereo OS developer', "the development files of the edition's stereo stack at the edition's versions (stereo-declare, stereo-layer, gl-stereo, Mesa, KWin, Qt and the Wayland protocols), Debian packaging tools, the stereo proof rig and the virtual display benches, the tools KDE's CI needs locally, and the edition's maintainer skills for humans and local or hosted AI partners; it brings the developer task"),
}
# The developer tasks are opt-in (Daniel, 2026-10-16: "just install the meta and start developing"): tasksel lists them,
# and sparky-stereo does not pull them in.
OPT_IN = {'developer', 'os-developer'}

# The development files of our stereo stack, at the repository's versions, in the Depends of the Stereo OS developer task.
OS_DEV_STACK = [f'{n} (>= {RV[n]})' for n in (
    'kwin-dev', 'libgbm-dev', 'libkscreen-dev', 'libnvidia-egl-wayland-dev', 'libstereo-declare-dev', 'libstereo-layer-dev',
    'libstereo-policy-dev', 'mesa-common-dev', 'plasma-wayland-protocols', 'qt6-base-dev', 'qt6-base-private-dev',
    'qt6-multimedia-dev')]
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
            rec = sorted(set(rec) | set(GAMING_LISTS) | {'sparky-stereo-game-performance'})
        if r in OPT_IN:
            rec = sorted(set(rec) | set(lst(r)))
        if r == 'os-developer':
            # Daniel, 2026-10-19: these instructions belong to distro developers, not regular developers.
            dep += ['task-sparky-stereo-developer', 'sparky-stereo-skills (>= 0.2.0~dev20261019)',
                    'dpkg-stereo (>= 0.1.7)'] + OS_DEV_STACK
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

# Breaks per meta-package: older builds that do not work with the stack we ship.
# libkf6idletime6 built against Qt 6.10 gets no Wayland interface from Qt 6.11 (QWaylandApplication
# revision 2), so no dim, screen-off or lock happens (Daniel, 2026-10-10: until our qt6-base carries it, ORDER item 31).
BREAKS = {
    'sparky-stereo-desktop': ['libkf6idletime6 (<< 6.30.0-2)'],
}

# name: (title line, body, depends, recommends)
META = {
    'sparky-stereo-desktop': (
        'Sparky Stereo desktop',
        'This meta package installs the desktop of Sparky Stereo OS: the look, console and system information of the edition, the Memory page in System Settings, time synchronisation, the Dolphin menu that converts audio files, VLC Stereo as the video player, and the applications beyond the KDE edition.',
        ['sparky-stereo-audio-convert', 'sparky-stereo-cec', 'sparky-stereo-console', 'sparky-stereo-info', 'sparky-stereo-look', 'sparky-stereo-memory-kcm', 'sparky-stereo-power-profiles', 'sparky-stereo-time'] + lst('look') + OURS_PLAYER,
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
        # NVIDIA's optional GDS module needs newer DKMS from its vendor repo.
        # Do not require that repository or DKMS version on other hardware.
        sorted(HARDWARE_OPTIONAL & set(lst('hardware'))) + ['sparky-stereo-dkms-compat']),
    'sparky-stereo-system': (
        'Sparky Stereo system',
        'This meta package installs the system tools of Sparky Stereo OS: Flatpak, snapshots, containers, Android support, the kernel settings (zram only where the hardware needs it), the Cushion Swap File and the groups every desktop user needs.',
        sorted(set(lst('system')) - SYSTEM_OPTIONAL) + STEREO_STACK + ['sparky-stereo-cushion-swap', 'sparky-stereo-kernel-settings', 'sparky-stereo-user-groups'],
        sorted(SYSTEM_OPTIONAL & set(lst('system')))),
    'linux-image-sparky-stereo': (
        'Sparky Stereo kernel',
        'This meta package installs the current stereo 3D kernel of Sparky Stereo OS.',
        [f'{KERNEL} (>= {RV[KERNEL]})'], []),
    'linux-headers-sparky-stereo': (
        'Sparky Stereo kernel headers',
        'This meta package installs the headers of the current stereo 3D kernel of Sparky Stereo OS, for DKMS modules.',
        ['linux-headers-' + KREL + f' (>= {RV["linux-headers-" + KREL]})', 'linux-image-sparky-stereo'], []),
    **{f'linux-{kind}-sparky-stereo-{fl}': (
        f'Sparky Stereo kernel{" headers" if kind == "headers" else ""}, {title}',
        f'This meta package installs the {"headers of the " if kind == "headers" else ""}current stereo 3D kernel of Sparky Stereo OS {what}'
        + (', for DKMS modules.' if kind == 'headers' else '.'),
        ([f'{flavour_image(fl)} (>= {RV[flavour_image(fl)]})'] if kind == 'image' else
         ['linux-headers-' + flavour_image(fl)[len('linux-image-'):]
          + f' (>= {RV["linux-headers-" + flavour_image(fl)[len("linux-image-"):]]})',
          f'linux-image-sparky-stereo-{fl}']), [])
       for fl, title, what in (('v3', 'x86-64-v3', 'built for x86-64-v3 processors (Intel Haswell, AMD Excavator and newer)'),
                               ('rt', 'real-time', 'with real-time preemption (PREEMPT_RT), an option for audio and low-latency work'))
       for kind in ('image', 'headers') if flavour_image(fl)},
    'sparky-stereo': (
        'Sparky Stereo OS',
        'This meta package installs Sparky Stereo OS, the stereo 3D edition of SparkyLinux: the desktop, gaming, languages, hardware support and system meta packages.',
        ['sparky-stereo-desktop', 'sparky-stereo-hardware-support',
         'sparky-stereo-languages', 'sparky-stereo-system'],
        ['sparky-stereo-tasks']),
}
META.update(tasks())
META['sparky-stereo'] = (META['sparky-stereo'][0], META['sparky-stereo'][1].replace('the desktop, gaming, languages, hardware support and system meta packages', 'the desktop, languages, hardware support and system meta packages, and every role task (gamer, designer, video creator, musician, scientist, student, simulator pilot and driver, maker, electrical and automation engineer); the two developer tasks are installed on request'), META['sparky-stereo'][2], META['sparky-stereo'][3] + sorted(k for k in META if k.startswith('task-') and k[len('task-sparky-stereo-'):] not in OPT_IN))
META['sparky-stereo-tasks'] = (
    'Sparky Stereo OS tasks for tasksel',
    'This package lists the role tasks of Sparky Stereo OS in tasksel, the Debian way: gamer, designer, video creator, musician, scientist, student, simulator pilot and driver, maker, electrical and automation engineer, developer and Stereo OS developer, with the 2D programs of science and education as their own tasks.',
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
        # A packaging-only rebuild must advance the meta version without
        # inventing a new kernel ABI or changing the image/header dependency.
        v = KVERSION + os.environ.get('KERNEL_META_VERSION_SUFFIX', '') if pkg.startswith('linux-') else version
        rec = sorted(set(rec) - set(dep))
        d = os.path.join(out, pkg)
        os.makedirs(os.path.join(d, 'DEBIAN'), exist_ok=True)
        doc = os.path.join(d, 'usr', 'share', 'doc', pkg)
        os.makedirs(doc, exist_ok=True)
        open(os.path.join(doc, 'copyright'), 'w').write(COPYRIGHT)
        size = subprocess.run(['du', '-sk', '--exclude=DEBIAN', d], capture_output=True, text=True).stdout.split()[0]
        f = [('Package', pkg), ('Version', v), ('Architecture', 'all'), ('Maintainer', MAINT),
             ('Installed-Size', size)]
        if dep:
            f.append(('Depends', ', '.join(dep)))
        if rec:
            f.append(('Recommends', ', '.join(rec)))
        if pkg in BREAKS:
            f.append(('Breaks', ', '.join(BREAKS[pkg])))
        f += [('Section', 'System'), ('Priority', 'optional'), ('Homepage', 'https://sparkylinux.org'),
              ('Description', title + '\n  ' + body)]
        with open(os.path.join(d, 'DEBIAN', 'control'), 'w') as c:
            c.write(''.join(f'{k}: {v}\n' for k, v in f))

main()
