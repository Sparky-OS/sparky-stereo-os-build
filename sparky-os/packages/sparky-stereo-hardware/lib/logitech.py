# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Logitech identity facts and the optional app center offer; no device I/O."""
from pathlib import Path
import re
import sys


def optional(facts, name):
    path = facts / name
    return path.read_text() if path.is_file() else ''


def devices(facts, data):
    known = {}
    for line in (data / 'peripherals/openlogi.ids').read_text().splitlines():
        if line and not line.startswith('#'):
            identifier, kind, source = line.split('\t')
            known.setdefault(kind, set()).add(identifier)
    usb = {f'{vendor.lower()}:{product.lower()}' for vendor, product in
           re.findall(r'\bID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\b', optional(facts, 'lsusb'))}
    found = usb & (known.get('receiver', set()) | known.get('litra', set()) | known.get('usb', set()))
    for block in optional(facts, 'hid-uevents').split('\n\n'):
        for bus, vendor, product in re.findall(r'HID_ID=([0-9A-Fa-f]+):([0-9A-Fa-f]+):([0-9A-Fa-f]+)', block):
            if int(vendor, 16) != 0x046d or int(bus, 16) not in (3, 5):
                continue
            identifier = f'046d:{int(product, 16):04x}'
            kind = 'bluetooth' if int(bus, 16) == 5 else 'usb'
            if identifier in known.get(kind, set()) or 'DRIVER=logitech-hidpp' in block.splitlines():
                found.add(identifier)
    found.update(line.strip().lower() for line in optional(facts, 'usb-video').splitlines()
                 if re.fullmatch(r'046d:[0-9a-fA-F]{4}', line.strip(), re.I))
    return sorted(found)


def usb_video(sysfs=Path('/sys')):
    """Read existing USB interface class metadata; never open a camera or hidraw node."""
    directory = sysfs / 'bus/usb/devices'
    if not directory.is_dir():
        return []
    found = set()
    for interface in directory.iterdir():
        cls = interface / 'bInterfaceClass'
        if not cls.is_file() or cls.read_text().strip().lower() != '0e':
            continue
        device = interface.resolve().parent
        vendor, product = device / 'idVendor', device / 'idProduct'
        if vendor.is_file() and product.is_file():
            value = vendor.read_text().strip() + ':' + product.read_text().strip()
            if re.fullmatch(r'[0-9a-fA-F]{4}:[0-9a-fA-F]{4}', value):
                found.add(value.lower())
    return sorted(found)


if __name__ == '__main__':
    if sys.argv[1:] != ['capture-video']:
        raise SystemExit(2)
    for identifier in usb_video():
        print(identifier)
