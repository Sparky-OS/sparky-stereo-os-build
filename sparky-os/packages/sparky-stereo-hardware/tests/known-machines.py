#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
"""Run only inside an isolated container with umockdev installed."""
import json
from pathlib import Path
import subprocess
import tempfile

recipe = Path(__file__).resolve().parent.parent
tool = recipe / 'bin/sparky-stereo-known-machines'
fixture = (recipe / 'tests/known-machines/vaio.umockdev').read_text()
table = json.loads((recipe / 'share/known-machines.json').read_text())


def run(device, data=table, success=True):
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        (root / 'devices').write_text(device)
        (root / 'table.json').write_text(json.dumps(data))
        result = subprocess.run(['umockdev-run', '-d', str(root / 'devices'),
                                 '--', 'python3', str(tool), '--table',
                                 str(root / 'table.json'), '--apply'],
                                capture_output=True, text=True)
        assert (result.returncode == 0) == success, result.stderr
        return json.loads(result.stdout) if success else result.stderr


for product in ['SVD13217CBW', 'SVD1321X9E', 'SVD132']:
    result = run(fixture.replace('SVD13217CBW', product))
    assert [entry['id'] for entry in result['matched']] == ['sony-vaio-duo-13']
    assert result['changes'] == []
    assert result['matched'][0]['corrections'] == []
    print('PASS documented DMI family:', product)

assert run(fixture.replace('SVD13217CBW', 'Other notebook'))['matched'] == []
assert run(fixture.split('\n\n', 1)[1])['matched'] == []
print('PASS unrelated and missing DMI: same USB camera does not imply a VAIO')

pci = '\n\nP: /devices/pci0000:00/0000:00:02.0\nE: SUBSYSTEM=pci\nA: vendor=0x8086\nA: device=0x0a16\n'
combined = {'version': 1, 'machines': [{'id': 'fixture-combined',
            'match': {'dmi_product': ['SVD132*'], 'usb': ['0bda:5722'],
                      'pci': ['8086:0a16']}, 'corrections': [], 'references': []}]}
assert len(run(fixture + pci, combined)['matched']) == 1
assert run(fixture, combined)['matched'] == []
assert run((fixture + pci).replace('idProduct=5722', 'idProduct=579f'),
           combined)['matched'] == []
print('PASS DMI, USB and PCI conjunctive matching')

unsafe = json.loads(json.dumps(table))
unsafe['machines'][0]['corrections'] = ['unreviewed-command']
assert 'no reviewed handler' in run(fixture, unsafe, False)
invalid = json.loads(json.dumps(table))
invalid['machines'][0]['match'] = {'device_command': ['anything']}
assert 'invalid machine match' in run(fixture, invalid, False)
print('PASS unsupported correction and unknown match fields fail visibly')
