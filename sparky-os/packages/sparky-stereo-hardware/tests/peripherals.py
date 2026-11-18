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
    'dmi-board-vendor': 'Some Board Maker\n', 'dmi-board-name': 'TEST\n', 'openlinkhub': 'no\n', 'openlinkhub-upstream': 'no\n', 'corectrl': 'no\n', 'lact-local': 'no\n', 'headsetcontrol-local': 'no\n',
}


def usb(*ids):
    return ''.join(f'Bus 001 Device {n + 2:03d}: ID {i} Test device\n' for n, i in enumerate(ids))


AMD = '03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 21 [Radeon RX 6800] [1002:73bf] (rev c1)\n'
INTEL = '00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics 630 [8086:3e92]\n'
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
    # the clash of 2026-11-06: an iCUE LINK System Hub. OpenLinkHub, the edition's package of upstream's program, is installed for it and
    # owns it; OpenRGB is not installed for it (Daniel, 2026-11-17: "I agree with the corsair plan - the user can always change it inside openrgb")
    ('an iCUE LINK hub', {'lsusb': usb(HUB)}, {'openlinkhub'}, {'openrgb', 'liquidctl'},
     ['fact\tperipheral\topenlinkhub\t' + HUB, f'owner\t{HUB}\topenlinkhub\tnot OpenRGB\tCorsair_iCUE_Link_System_Hub'], ['action\topenrgb-session']),
    # the same hub with upstream's own install on the machine (/opt/OpenLinkHub): the person's, so the package is not planned beside it
    ('an iCUE LINK hub, upstream\'s own OpenLinkHub installed', {'lsusb': usb(HUB), 'openlinkhub': 'yes\n', 'openlinkhub-upstream': 'yes\n'},
     set(), {'openlinkhub', 'openrgb', 'liquidctl'},
     ['fact\tperipheral\topenlinkhub-upstream\t' + HUB, f'owner\t{HUB}\topenlinkhub\tnot OpenRGB\tCorsair_iCUE_Link_System_Hub'], ['action\topenrgb-session']),
    # a cooler both liquidctl and OpenRGB drive: OpenLinkHub's, both kept out
    ('an H100i v2 cooler', {'lsusb': usb(PSU_COOLER)}, {'openlinkhub'}, {'openrgb', 'liquidctl'},
     [f'owner\t{PSU_COOLER}\topenlinkhub\tnot OpenRGB\tCorsair_H100i_v2', f'owner\t{PSU_COOLER}\topenlinkhub\tnot liquidctl\tCorsair_H100i_v2'], []),
    ('a Lighting Node Pro', {'lsusb': usb('1b1c:0c0b')}, {'openlinkhub'}, {'openrgb', 'liquidctl'}, ['fact\tperipheral\topenlinkhub\t1b1c:0c0b'], []),
    # a power supply liquidctl alone lists
    ('an HX750i power supply', {'lsusb': usb('1b1c:1c05')}, {'openlinkhub'}, {'liquidctl', 'openrgb'}, ['fact\tperipheral\topenlinkhub\t1b1c:1c05'], []),
    # Corsair keyboards, mice and the LT100 tower stay OpenRGB's: OpenLinkHub drives them too, the edition does not carry it for them
    ('a Corsair K95 keyboard', {'lsusb': usb('1b1c:1b11')}, {'openrgb'}, {'openlinkhub', 'liquidctl'},
     ['fact\tperipheral\topenrgb\t1b1c:1b11', 'action\topenrgb-session'], []),
    ('a Corsair Scimitar mouse', {'lsusb': usb('1b1c:1b1e')}, {'openrgb'}, {'openlinkhub'}, ['action\topenrgb-session'], []),
    ('a Corsair LT100 lighting tower', {'lsusb': usb('1b1c:0c23')}, {'openrgb'}, {'openlinkhub'}, ['action\topenrgb-session'], []),
    # a hub and a keyboard together: each goes to its own tool
    ('a hub and a keyboard', {'lsusb': usb(HUB, '1b1c:1b11')}, {'openlinkhub', 'openrgb'}, {'liquidctl'},
     ['fact\tperipheral\topenlinkhub\t' + HUB, 'fact\tperipheral\topenrgb\t1b1c:1b11'], []),
    # headsets (milestone 10): HeadsetControl drives the battery, sidetone and lights through the headset's own interface; a headset OpenRGB lists
    # too gets both (no clash has been seen, and the person can take either away)
    ('a HyperX headset', {'lsusb': usb('03f0:018b')}, {'headsetcontrol', 'sparky-stereo-headset'}, {'openrgb', 'openlinkhub'}, ['fact\tperipheral\theadsetcontrol\t03f0:018b'], []),
    ('a Logitech headset that OpenRGB lists too', {'lsusb': usb('046d:0a87')}, {'headsetcontrol', 'sparky-stereo-headset', 'openrgb'}, set(),
     ['fact\tperipheral\theadsetcontrol\t046d:0a87', 'fact\tperipheral\topenrgb\t046d:0a87'], []),
    ('a HyperX headset and a HeadsetControl made by upstream\'s makefile', {'lsusb': usb('03f0:018b'), 'headsetcontrol-local': 'yes\n'}, set(), {'headsetcontrol', 'sparky-stereo-headset'},
     ['fact\tperipheral\theadsetcontrol-local\t03f0:018b'], []),
    # LACT (milestone 10): an AMD display controller gets LACT, which owns the card; CoreCtrl is not installed for it
    ('an AMD Radeon card', {'lspci': AMD}, {'lact'}, {'corectrl', 'openrgb'},
     ['fact\tperipheral\tlact\t1002:73bf', 'owner\t1002:73bf\tlact\tnot CoreCtrl\tAMD graphics card'], []),
    ('an AMD Radeon card and a CoreCtrl the person installed', {'lspci': AMD, 'corectrl': 'yes\n'}, set(), {'lact', 'corectrl'},
     ['fact\tperipheral\tlact-not-planned\t1002:73bf'], ['owner\t1002:73bf\tlact\tnot CoreCtrl\tAMD graphics card']),
    ('an AMD Radeon card and a LACT made by upstream\'s makefile', {'lspci': AMD, 'lact-local': 'yes\n'}, set(), {'lact'},
     ['fact\tperipheral\tlact-not-planned\t1002:73bf'], []),
    ('an Intel graphics controller', {'lspci': INTEL}, set(), {'lact'}, [], []),
    # a device only OpenRGB drives stays OpenRGB's
    ('a Wraith Prism', {'lsusb': usb(WRAITH)}, {'openrgb'}, {'openlinkhub'}, ['action\topenrgb-session'], []),
    # a lights-only controller that OpenRGB and liquidctl both list (liquidctl names it "LED Controller"): OpenRGB's; liquidctl is for coolers and fans
    ('an ASUS Aura LED controller', {'lsusb': usb('0b05:18f3')}, {'openrgb'}, {'liquidctl'},
     ['owner\t0b05:18f3\topenrgb\tnot liquidctl\tASUS Aura LED Controller', 'action\topenrgb-session'], []),
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
