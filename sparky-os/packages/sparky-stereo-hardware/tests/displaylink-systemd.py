#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/14
# Copyright 2026 under the GNU GPL3 License
"""Destructive fixtures: run only as root in a disposable systemd container.

Arguments: extracted vendor package root, hardware recipe, evidence directory.
No DisplayLink binary or kernel module is executed. The real vendor unit,
activation script, systemd, journald and problems engine are exercised.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

vendor, recipe, out = map(Path, sys.argv[1:4])
installed = sys.argv[4:] == ['--installed']
assert Path('/run/systemd/system').is_dir() and os.environ.get('container') == 'docker'
unit = 'displaylink-driver.service'


def call(args, check=True, **kwargs):
    result = subprocess.run(args, text=True, capture_output=True,
                            timeout=30, **kwargs)
    if check and result.returncode:
        raise RuntimeError(f'{args}: {result.stderr}')
    return result


def write(path, text, executable=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


def state():
    result = call(['systemctl', 'show', unit, '-p', 'ActiveState', '-p',
                   'SubState', '-p', 'NRestarts', '-p', 'Result']).stdout
    return dict(line.split('=', 1) for line in result.splitlines())


def attempts():
    return len(Path('/run/uv569-modprobe-attempts').read_text().splitlines())


def records():
    result = call(['sparky-stereo-problems', 'list', '--json',
                   'sparky-stereo-hardware']).stdout
    return [p for p in json.loads(result) if p['key'] == 'displaylink-start']


vendor_unit = vendor / 'usr/lib/systemd/system' / unit
installed_unit = Path('/usr/lib/systemd/system') / unit
dest = Path('/usr/lib/systemd/system') / (unit + '.d')
helper = Path('/usr/lib/sparky-stereo-hardware/displaylink-status')
if installed:
    installed_dropin = (dest / '40-sparky-stereo-hardware.conf').read_bytes()
    installed_helper = helper.read_bytes()
for name in ['40-sparky-stereo-hardware.conf', '50-sparky-stereo-problems.conf']:
    (Path('/usr/lib/systemd/system') / (unit + '.d') / name).unlink(missing_ok=True)
Path('/run/uv569-module-ready').unlink(missing_ok=True)
Path('/run/uv569-modprobe-attempts').unlink(missing_ok=True)
shutil.copyfile(vendor_unit, installed_unit)
write('/usr/lib/displaylink-driver/DisplayLinkManager', '#!/bin/sh\nexec sleep infinity\n', True)
write('/usr/local/bin/modprobe', '''#!/bin/sh
echo attempt >> /run/uv569-modprobe-attempts
test -e /run/uv569-module-ready && exit 0
echo 'fixture evdi: Key was rejected by service' >&2
exit 1
''', True)
write('/usr/local/bin/dkms', "#!/bin/sh\necho 'fixture evdi build cannot repair the rejected key' >&2\nexit 1\n", True)
Path('/usr/src/evdi-fixture').mkdir(exist_ok=True)
dropins = Path('/etc/systemd/system') / (unit + '.d')
write(dropins / '10-fixture-path.conf', '[Service]\nEnvironment=PATH=/usr/local/bin:/usr/sbin:/usr/bin\n')
try:
    call(['systemctl', 'daemon-reload'])
    call(['systemctl', 'start', unit], check=False)
    time.sleep(12)
    red = state()
    assert attempts() >= 3 and int(red['NRestarts']) >= 2, red
    print('PASS red: vendor unit retries a permanent pre-step failure:', red, flush=True)
    call(['systemctl', 'stop', unit])
    (out / 'displaylink-red-state.json').write_text(json.dumps(red, indent=2))

    dest.mkdir(exist_ok=True)
    if installed:
        (dest / '40-sparky-stereo-hardware.conf').write_bytes(installed_dropin)
        assert helper.read_bytes() == installed_helper
    else:
        shutil.copyfile(recipe / 'share/systemd/displaylink-driver.service.d/40-sparky-stereo-hardware.conf',
                        dest / '40-sparky-stereo-hardware.conf')
    (dest / '50-sparky-stereo-problems.conf').symlink_to('/dev/null')
    helper.parent.mkdir(exist_ok=True)
    if not installed:
        shutil.copyfile(recipe / 'bin/sparky-stereo-displaylink-status', helper)
        helper.chmod(0o755)
        call(['sparky-stereo-problems', 'catalog', 'sparky-stereo-hardware',
              str(recipe / 'problems-lang'), '/usr/lib/systemd/catalog',
              '--subject', 'LOCAL19=LOCAL20'])
    call(['systemctl', 'daemon-reload'])
    before = attempts()
    call(['systemctl', 'start', unit], check=False)
    time.sleep(12)
    green = state()
    assert attempts() == before + 1, (before, attempts())
    assert green['ActiveState'] == 'failed' and green['NRestarts'] == '0', green
    kept = records()
    assert len(kept) == 1 and 'Key was rejected' in kept[0]['output'], kept
    assert not kept[0].get('repair'), kept
    print('PASS green: one failed module attempt, no retry; actual cause kept once', flush=True)
    (out / 'displaylink-green-state.json').write_text(json.dumps(green, indent=2))
    (out / 'displaylink-problem.json').write_text(json.dumps(kept, indent=2))

    Path('/run/uv569-module-ready').touch()
    # The vendor script's two-argument USB-add branch counts actual sysfs USB
    # identifiers. umockdev provides a later DisplayLink plug, not host devices.
    result = call(['umockdev-run', '-d', str(recipe / 'tests/known-machines/displaylink.umockdev'),
                   '--', 'sh', str(vendor / 'usr/lib/displaylink-driver/udev.sh'),
                   '/dev', '/devices/usb1/1-2'], env=os.environ | {'ACTION': 'add'})
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and state()['ActiveState'] != 'active':
        time.sleep(0.1)
    assert state()['ActiveState'] == 'active', (state(), result.stderr)
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and records():
        time.sleep(0.1)
    assert records() == []
    assert installed_unit.read_bytes() == vendor_unit.read_bytes()
    print('PASS later USB add: unchanged vendor script starts daemon; record clears', flush=True)
    (out / 'displaylink-ready-state.json').write_text(json.dumps(state(), indent=2))
    for language in ['en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW']:
        assert 'LOCAL20=' in (recipe / 'problems-lang' / language).read_text()
    print('PASS all ten catalogues carry the failure and repair guidance', flush=True)
finally:
    call(['systemctl', 'stop', unit], check=False)
    journal = call(['journalctl', '--no-pager', '-u', unit, '-o', 'short-monotonic']).stdout
    (out / 'displaylink-journal.log').write_text(journal)
