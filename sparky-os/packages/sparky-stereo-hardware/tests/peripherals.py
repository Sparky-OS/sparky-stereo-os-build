#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
"""Lights and peripherals by detection (ORDER 108, milestone 6): the plan for recorded USB listings, board makers and OpenLinkHub.

Runs inside the container tests/container-detection.sh builds. Each case is a set of fact files; the plan comes from
`sparky-stereo-hardware --auto --dry-run --fixture`, so the tool's own path is what is tested.
"""
import pathlib
import subprocess
import tempfile

assert pathlib.Path('/.dockerenv').exists(), 'Run in Docker only'
tool = '/usr/bin/sparky-stereo-hardware'
base = {
    'lspci': '', 'lsusb': '', 'cpuinfo': 'vendor_id : AuthenticAMD\n', 'laptop': '1\n', 'architecture': 'amd64\n',
    'hid-uevents': '', 'input-properties': '', 'firmware-packages': '', 'nvidia-detect': 'No NVIDIA GPU detected.\n',
    'dmi-board-vendor': 'Some Board Maker\n', 'dmi-board-name': 'TEST\n',
}


def usb(*ids):
    return ''.join(f'Bus 001 Device {n + 2:03d}: ID {i} Test device\n' for n, i in enumerate(ids))


HUB, PSU_COOLER, WRAITH = '1b1c:0c3f', '1b1c:0c09', '2516:0051'
cases = [
    # name, changed facts, packages that must be in the plan, packages that must not, lines that must be in it, lines that must not
    ('no device', {}, set(), {'openrgb', 'solaar', 'piper', 'ratbagd', 'liquidctl', 'g810-led', 'openrazer-daemon', 'i2c-tools'},
     [], ['action\topenrgb-session', 'action\ti2c-dev']),
    ('a Logitech Unifying receiver', {'lsusb': usb('046d:c52b')}, {'solaar'}, {'openrgb', 'piper'}, ['fact\tperipheral\tsolaar\t046d:c52b'],
     ['action\topenrgb-session']),
    ('a Logitech gaming mouse (libratbag)', {'lsusb': usb('046d:c097')}, {'ratbagd', 'piper'}, {'solaar'}, ['fact\tperipheral\tratbag\t046d:c097'], []),
    ('an AMD Wraith Prism cooler light', {'lsusb': usb(WRAITH)}, {'openrgb'}, {'liquidctl'}, ['action\topenrgb-session'], ['action\ti2c-dev']),
    ('a Logitech G810 keyboard', {'lsusb': usb('046d:c337')}, {'g810-led'}, set(), ['fact\tperipheral\tg810-led\t046d:c337'], []),
    ('a Razer keyboard', {'lsusb': usb('1532:0243')}, {'openrazer-daemon', 'openrazer-driver-dkms', 'openrgb'}, set(),
     ['fact\tperipheral\topenrazer\t1532:0243'], []),
    # the clash of 2026-11-06: an iCUE LINK System Hub, no OpenLinkHub on the machine: OpenRGB owns it
    ('an iCUE LINK hub, OpenLinkHub absent', {'lsusb': usb(HUB), 'openlinkhub': 'no\n'}, {'openrgb'}, set(),
     ['fact\tperipheral\topenrgb\t' + HUB, 'action\topenrgb-session'], []),
    # OpenLinkHub installed: it owns the hub, OpenRGB is not installed for it, no session start for a device OpenRGB would not open
    ('an iCUE LINK hub, OpenLinkHub installed', {'lsusb': usb(HUB), 'openlinkhub': 'yes\n'}, set(), {'openrgb', 'liquidctl'},
     [f'owner\t{HUB}\topenlinkhub\tnot OpenRGB\tCorsair_iCUE_Link_System_Hub'], ['action\topenrgb-session']),
    # a cooler both liquidctl and OpenRGB drive
    ('an H100i v2 cooler, OpenLinkHub absent', {'lsusb': usb(PSU_COOLER), 'openlinkhub': 'no\n'}, {'openrgb', 'liquidctl'}, set(), [], []),
    ('an H100i v2 cooler, OpenLinkHub installed', {'lsusb': usb(PSU_COOLER), 'openlinkhub': 'yes\n'}, set(), {'openrgb', 'liquidctl'},
     [f'owner\t{PSU_COOLER}\topenlinkhub\tnot OpenRGB\tCorsair_H100i_v2', f'owner\t{PSU_COOLER}\topenlinkhub\tnot liquidctl\tCorsair_H100i_v2'], []),
    # a device only OpenRGB drives stays OpenRGB's even where OpenLinkHub is installed
    ('a Wraith Prism, OpenLinkHub installed', {'lsusb': usb(WRAITH), 'openlinkhub': 'yes\n'}, {'openrgb'}, set(), ['action\topenrgb-session'], []),
    # the SMBus: a desktop of a board maker OpenRGB's detectors name, per CPU maker (OpenRGB's SMBusAccess.md); never a laptop
    ('a Gigabyte desktop board, AMD', {'dmi-board-vendor': 'Gigabyte Technology Co., Ltd.\n'}, {'i2c-tools', 'openrgb'}, set(),
     ['action\ti2c-dev', 'fact\tsmbus-modules\ti2c-dev i2c-piix4', 'action\topenrgb-session'], []),
    ('an MSI desktop board, Intel', {'dmi-board-vendor': 'Micro-Star International Co., Ltd.\n', 'cpuinfo': 'vendor_id : GenuineIntel\n'},
     {'i2c-tools', 'openrgb'}, set(), ['fact\tsmbus-modules\ti2c-dev i2c-i801'], []),
    ('a Gigabyte laptop board', {'dmi-board-vendor': 'Gigabyte Technology Co., Ltd.\n', 'laptop': '0\n'}, set(), {'i2c-tools', 'openrgb'}, [],
     ['action\ti2c-dev', 'action\topenrgb-session']),
]
failed = 0
with tempfile.TemporaryDirectory() as tmp:
    directory = pathlib.Path(tmp)
    for name, changes, want, refuse, lines_in, lines_out in cases:
        for key in list(directory.iterdir()):
            key.unlink()
        for key, value in (base | changes).items():
            (directory / key).write_text(value)
        out = subprocess.run([tool, '--auto', '--dry-run', '--fixture', str(directory)], text=True, capture_output=True, check=True).stdout
        lines = out.splitlines()
        packages = {line.split('\t')[1] for line in lines if line.startswith('package\t')}
        problems = []
        if not want <= packages:
            problems.append(f'missing packages {sorted(want - packages)}')
        if packages & refuse:
            problems.append(f'unwanted packages {sorted(packages & refuse)}')
        problems += [f'missing line {l!r}' for l in lines_in if l not in lines]
        problems += [f'unwanted line {l!r}' for l in lines_out if l in lines]
        if problems:
            failed += 1
            print(f'FAIL {name}: {problems}\n{out}')
        else:
            print(f'PASS {name}: {sorted(packages - {"amd64-microcode", "intel-microcode", "thermald"}) or "no peripheral package"}')
assert not failed, f'{failed} cases failed'
