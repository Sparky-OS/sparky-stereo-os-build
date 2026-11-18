#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Regenerate numeric identities from separately obtained upstream source trees."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('--openlogi', type=Path, required=True)
parser.add_argument('--openlogi-commit', required=True)
parser.add_argument('--kernel-hidpp', type=Path, required=True)
parser.add_argument('--kernel-ids', type=Path, required=True)
parser.add_argument('--kernel-commit', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
for commit in (args.openlogi_commit, args.kernel_commit):
    if not re.fullmatch('[0-9a-f]{40}', commit):
        parser.error('source commits must be full hexadecimal commit IDs')
records = set()
base = f'https://github.com/AprilNEA/OpenLogi/blob/{args.openlogi_commit}/'
receiver = 'crates/openlogi-device-registry/src/receiver.rs'
text = (args.openlogi / receiver).read_text()
table = text.split('pub const RECEIVERS:', 1)[1].split('];', 1)[0]
for match in re.finditer(r'ReceiverDescriptor::logitech\(\s*(0x[0-9a-fA-F]+)', table):
    product = int(match.group(1), 16)
    line = text[:text.index(table) + match.start()].count('\n') + 1
    records.add((f'046d:{product:04x}', 'receiver', base + receiver + f'#L{line}'))
litra = 'crates/openlogi-device-registry/src/litra.rs'
text = (args.openlogi / litra).read_text()
for match in re.finditer(r'pub const LITRA_\w+_PRODUCT_ID: u16 = (0x[0-9a-fA-F]+)', text):
    records.add((f'046d:{int(match.group(1),16):04x}', 'litra', base + litra + f'#L{text[:match.start()].count(chr(10))+1}'))
defines = dict(re.findall(r'^#define\s+(USB_DEVICE_ID_LOGITECH_\w+)\s+(0x[0-9a-fA-F]+)', args.kernel_ids.read_text(), re.M))
text = args.kernel_hidpp.read_text()
for match in re.finditer(r'HID_(USB|BLUETOOTH)_DEVICE\(USB_VENDOR_ID_LOGITECH,\s*(0x[0-9a-fA-F]+|USB_DEVICE_ID_LOGITECH_\w+)\)', text):
    raw = match.group(2)
    product = int(defines.get(raw, raw), 16)
    source = f'https://github.com/torvalds/linux/blob/{args.kernel_commit}/drivers/hid/hid-logitech-hidpp.c#L{text[:match.start()].count(chr(10))+1}'
    records.add((f'046d:{product:04x}', match.group(1).lower(), source))
records.add(('046d:*', 'uvc', base + 'crates/openlogi-camera/src/linux.rs'))
args.output.write_text('# Logitech identity metadata: ID, transport/family, source. No upstream program is included.\n' +
                       '\n'.join('\t'.join(row) for row in sorted(records)) + '\n')
print(f'{len(records)} sourced identity rows')
