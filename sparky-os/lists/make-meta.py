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
# Last update 2026/10/02
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAINT = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'

def lst(name):
    return [l.strip() for l in open(os.path.join(HERE, name + '.list'))
            if l.strip() and not l.startswith('#')]

# Packages of ours (sparky-os/repo) the lists do not carry, because apt did not offer them
# when make-lists.py ran.
OURS_HARDWARE = ['pipewire-bluez5-codec-aac']

# Optional inside an otherwise essential list.
HARDWARE_OPTIONAL = {'displaylink-driver', 'evdi-dkms', 'hw-probe', 'memtest86+', 'inxi'}
SYSTEM_OPTIONAL = {'distrobox', 'timeshift', 'waydroid'}

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
        lst('runtimes'),
        lst('gaming') + lst('games')),
    'sparky-stereo-languages': (
        'Sparky Stereo languages',
        'This meta package installs the languages of Steam for the applications Sparky Stereo OS ships: dictionaries, hyphenation, fonts, help and input methods.',
        [],
        lst('languages')),
    'sparky-stereo-hardware-support': (
        'Sparky Stereo hardware support',
        'This meta package installs the firmware, microcode, video acceleration and the tools the hardware setup of Sparky Stereo OS uses. The NVIDIA driver is not included: the hardware setup installs it when it finds the card.',
        sorted(set(lst('hardware')) - HARDWARE_OPTIONAL) + OURS_HARDWARE,
        sorted(HARDWARE_OPTIONAL & set(lst('hardware')))),
    'sparky-stereo-system': (
        'Sparky Stereo system',
        'This meta package installs the system tools of Sparky Stereo OS: Flatpak, snapshots, containers, Android support and zram.',
        sorted(set(lst('system')) - SYSTEM_OPTIONAL),
        sorted(SYSTEM_OPTIONAL & set(lst('system')))),
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
        rec = sorted(set(rec) - set(dep))
        d = os.path.join(out, pkg)
        os.makedirs(os.path.join(d, 'DEBIAN'), exist_ok=True)
        size = subprocess.run(['du', '-sk', '--exclude=DEBIAN', d], capture_output=True, text=True).stdout.split()[0]
        f = [('Package', pkg), ('Version', version), ('Architecture', 'all'), ('Maintainer', MAINT),
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
