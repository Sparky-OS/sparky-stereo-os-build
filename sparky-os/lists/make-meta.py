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
# Last update 2026/10/04
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

# name: (title line, body, depends, recommends)
META = {
    'sparky-stereo-desktop': (
        'Sparky Stereo desktop',
        'This meta package installs the desktop of Sparky Stereo OS: the look, console and system information of the edition, time synchronisation and the applications beyond the KDE edition.',
        ['sparky-stereo-console', 'sparky-stereo-info', 'sparky-stereo-look', 'sparky-stereo-time'] + lst('look'),
        lst('apps')),
    'sparky-stereo-gaming': (
        'Sparky Stereo gaming',
        'This meta package installs the gaming tools, the games and the runtimes third-party programs and games expect, for Sparky Stereo OS. The emulators are not included: they install from APTus Stereo AppCenter.',
        # Depends only where the name is no versioned library (Debian renames those at every
        # transition, which would make the meta-package uninstallable); why each is needed:
        ['ffmpeg',      # the media tools games and launchers call
         'libvulkan1',  # the Vulkan loader (stable name) every DXVK/VKD3D game needs
         'python3'],    # the scripts of Lutris, protonup and game tools
        sorted(set(lst('runtimes')) - {'ffmpeg', 'libvulkan1', 'python3'}) + lst('gaming') + lst('games')),
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
        ['sparky-stereo-desktop', 'sparky-stereo-gaming', 'sparky-stereo-hardware-support',
         'sparky-stereo-languages', 'sparky-stereo-system'],
        []),
}

def main():
    version, out = sys.argv[1:3]
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
