#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Append the winebus EV_BTN patch (ORDER 15) to an already prepared Wine source: the published +stereo3d7+lc1 source, three patches, one changelog entry."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'repo'))
import reproducible


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('version')
    args = parser.parse_args()
    source = args.source.resolve()
    recipe = Path(__file__).resolve().parent
    stamp = reproducible.recipe_epoch([recipe])
    environment = os.environ | {
        'DEBFULLNAME': 'Daniel Ramos (Capitain Jack)',
        'DEBEMAIL': 'Capitain_Jack@yahoo.com',
        'QUILT_PATCHES': 'debian/patches',
    }
    old = subprocess.check_output(['dpkg-parsechangelog', '-S', 'Version'], cwd=source, text=True).strip()
    subprocess.run(['dpkg', '--compare-versions', args.version, 'gt', old], check=True)
    patches = [
        ('input/0001-winebus-udev-ev-btn.patch', 'wine-ev-btn-udev.patch',
         'winebus (udev backend): report a joystick\'s buttons from the kernel\'s EV_BTN event, so a device with more than 80 buttons shows them all; the idea of Wine merge request 9853 (Tomasz Pakula) ported to the lnxev code of Wine 10.0; retain all stereo patches and fixes.'),
        ('input/0002-winebus-udev-event-nodes.patch', 'wine-udev-event-nodes.patch',
         'winebus (udev backend): take only the eventN nodes of the input subsystem; joydev\'s jsN nodes were read as input events and gave garbage.'),
        ('input/0003-dinput-hid-joystick-button-128.patch', 'wine-dinput-button-128.patch',
         'dinput: a HID joystick\'s button 128 is a button (usage 128 was ignored as extraneous).'),
    ]
    series = source / 'debian/patches/series'
    for patch_name, _, _ in patches:
        destination = source / 'debian/patches' / patch_name
        if destination.exists():
            raise ValueError('Refusing to replace an existing Wine patch')
        if patch_name in series.read_text():
            raise ValueError('Fix is already in the patch series')
    for retained in ('debian/sparky-lean-preserve.json', 'debian/vulkan-registry/provenance.json',
                     'debian/patches/stereo3d/0005-winex11-quad-buffer-drawable-size.patch',
                     'debian/patches/stereo3d/0006-winex11-popup-metadata.patch',
                     'debian/patches/stereo3d/0007-winex11-vulkan-child-lifecycle.patch',
                     'debian/patches/fixes/temporary-directory-ownership.patch'):
        if not (source / retained).is_file():
            raise ValueError('Expected prepared Wine input: ' + retained)
    rules = (source / 'debian/rules').read_text()
    if 'sparky-lean-toolkit' not in rules or '--enable-archs=x86_64,i386' not in rules:
        raise ValueError('Expected existing LC and WoW64 integration')
    (source / 'debian/patches/input').mkdir(exist_ok=True)
    for patch_name, recipe_name, _ in patches:
        shutil.copy2(recipe / 'patches' / recipe_name, source / 'debian/patches' / patch_name)
        with series.open('a') as stream:
            stream.write('\n' + patch_name + '\n')
    subprocess.run(['quilt', 'push', '-a'], cwd=source, env=environment, check=True)
    subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--newversion', args.version, '--distribution', 'UNRELEASED', patches[0][2]],
                   cwd=source, env=environment, check=True)
    for _, _, message in patches[1:]:
        subprocess.run(['dch', '--date', reproducible.rfc2822(stamp), '--append', message], cwd=source, env=environment, check=True)
    subprocess.run(['sh', 'debian/scripts/check-control'], cwd=source, env=environment, check=True)
    reproducible.normalize_tree(source, stamp)


if __name__ == '__main__':
    main()
