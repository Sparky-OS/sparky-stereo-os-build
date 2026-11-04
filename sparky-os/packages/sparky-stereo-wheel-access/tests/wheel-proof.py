#!/usr/bin/python3
"""ORDER 346f-1 (U27): a wheel control that is there and cannot be set is kept; one the model lacks is not.

Runs in a container as root with the engine installed. The three drivers' udev rules (the directory given) are read by
the installed udev (udevadm test over umockdev's synthetic devices, as study/packages/rigs/check-wheel-udev.py does), the
commands udev would run are executed on a made-up sysfs folder holding some of the driver's controls, and the problems
the engine keeps are compared with the expected ones:
  1. the group games exists: every present control is games-owned and group-writable, no problem, no control invented;
  2. the group games is gone (renamed away; the failure): the commands are run again on controls that are there, the engine keeps a
     problem for that device naming them; the package's published rules keep nothing and exit 0;
  3. the group is back and the commands run again: the problem is cleared.
Usage: wheel-proof.py RULES_DIR      exit 0 only when every check passes (the published rules fail it: red)
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

rules_dir = Path(sys.argv[1])
fails = []
RUNS = re.compile(r'^\s*RUN\{program\} : (.*)$', re.M)


def check(ok, text):
    print('PASS' if ok else 'FAIL', text)
    if not ok:
        fails.append(text)


def sh(*cmd, **kw):
    return subprocess.run(cmd, text=True, capture_output=True, **kw)


def kept():
    out = sh('sparky-stereo-problems', 'list', '--json', 'sparky-stereo-wheel-access').stdout
    return json.loads(out or '[]')


def clear_all():
    sh('sparky-stereo-problems', 'clear', '--all', 'sparky-stereo-wheel-access')


def fixture(vid, pid, driver, subsystem, leaf, attrs=()):
    hid = f'0003:{vid.upper().zfill(8)}:{pid.upper().zfill(8)}.0001'
    base = '/devices/usb1/1-1'
    text = f'P: {base}\nE: SUBSYSTEM=usb\nE: DEVTYPE=usb_device\nA: idVendor={vid}\nA: idProduct={pid}\n\n'
    text += f'P: {base}/1-1:1.0\nE: SUBSYSTEM=usb\nE: DEVTYPE=usb_interface\n\n'
    text += f'P: {base}/1-1:1.0/{hid}\nE: SUBSYSTEM=hid\nE: HID_ID=0003:{vid.upper().zfill(8)}:{pid.upper().zfill(8)}\nE: DRIVER={driver}\n'
    for name in attrs:
        text += f'A: {name}=1\n'
    text += '\n'
    path = f'{base}/1-1:1.0/{hid}'
    if subsystem != 'hid':
        path += '/' + leaf
        text += f'P: {path}\nE: SUBSYSTEM={subsystem}\n\n'
    return text, path


def udev_runs(text, path, scratch):
    f = Path(scratch) / 'device.umockdev'
    f.write_text(text)
    r = sh('umockdev-run', '-d', str(f), '--', 'udevadm', 'test', '--action=add', '--resolve-names=never', '/sys' + path)
    assert r.returncode == 0, r.stderr[-1500:]
    return [c for c in RUNS.findall(r.stdout + r.stderr) if 'chown' in c or 'wheel-access' in c]


def run_commands(runs, path, sysdir):
    """What udev does with RUN: the program, with %S%p expanded to the made-up sysfs folder."""
    results = []
    for command in runs:
        assert '/sys' + path in command, command
        results.append(sh('sh', '-c', command.replace('/sys' + path, str(sysdir))))
    return results


def make_sysdir(root, name, present, mode):
    d = Path(root) / name
    d.mkdir()
    for attr in present:
        (d / attr).write_text('1\n')
        (d / attr).chmod(mode)
        os.chown(d / attr, 0, 0)
    return d


def state(d, attrs):
    out = {}
    for a in attrs:
        st = (d / a).stat()
        out[a] = (shutil.os.popen(f'stat -c %G "{d / a}"').read().strip(), st.st_mode & 0o777)
    return out


# (label, vid, pid, driver, subsystem, leaf, hid attrs for TEST, controls present, controls absent, mode wanted)
cases = [
    ('new-lg4ff', '046d', 'c24f', 'logitech', 'hid', None, ['range'], ['range', 'gain', 'autocenter'], ['ffb_leds'], 'g+w'),
    ('hid-tmff2', '044f', 'b66e', 'tmff2', 'hid', None, ['range'], ['range', 'gain'], ['alternate_modes'], 'g+w'),
    ('fanatec wheel', '0eb7', '0006', 'fanatec', 'hid', None, [], ['range', 'display'], ['load', 'rumble'], None),
    ('fanatec tuning', '0eb7', '0006', 'fanatec', 'ftec_tuning', 'ftec_tuning/0003:0EB7:0006.0001', [], ['advanced_mode', 'SLOT'], ['RESET'], None),
    ('fanatec leds', '0eb7', '0006', 'fanatec', 'leds', 'leds/0003:0EB7:0006.0001::RPM1', [], ['brightness', 'multi_intensity'], [], '660'),
]
etc = Path('/etc/udev/rules.d')
etc.mkdir(parents=True, exist_ok=True)
for rule in rules_dir.glob('*.rules'):
    shutil.copy(rule, etc / rule.name)
clear_all()

with tempfile.TemporaryDirectory(dir='/mnt/build/no-fallbacks-drivers-346f1/tmp') as scratch:
    for label, vid, pid, driver, subsystem, leaf, tests, present, absent, want_mode in cases:
        text, path = fixture(vid, pid, driver, subsystem, leaf, attrs=tests)
        runs = udev_runs(text, path, scratch)
        check(bool(runs), f'{label}: udev queues the controls command')
        # 1. the group is there
        d = make_sysdir(scratch, label.replace(' ', '_') + '-ok', present, 0o644)
        results = run_commands(runs, path, d)
        st = state(d, present)
        okgroup = all(g == 'games' for g, m in st.values())
        okmode = want_mode is None or all(m & 0o020 for g, m in st.values())
        check(okgroup and okmode, f'{label}: present controls are games-owned (and group-writable where asked): {st}')
        check(not any((d / a).exists() for a in absent), f'{label}: controls the model lacks are not made')
        check(all(r.returncode == 0 for r in results) and kept() == [], f'{label}: nothing wrong, exit 0 and no problem kept')
        # 2. the group is gone: the controls are there and cannot be set
        sh('groupmod', '-n', 'games-gone', 'games')
        d2 = make_sysdir(scratch, label.replace(' ', '_') + '-bad', present, 0o644)
        results = run_commands(runs, path, d2)
        problems = kept()
        named = problems and all(a in json.dumps(problems[0]) for a in present)
        check(len(problems) == 1 and named, f'{label}: failed controls are kept as a problem naming them: {[(p["key"], p.get("text", "")[:90]) for p in problems]}')
        check(any(r.returncode != 0 for r in results), f'{label}: the command says it failed (exit status)')
        # 3. the group is back and the same wheel's controls are set up again
        sh('groupmod', '-n', 'games', 'games-gone')
        results = run_commands(runs, path, d2)
        check(kept() == [] and all(r.returncode == 0 for r in results), f'{label}: set up again, the problem is cleared')
        clear_all()

if fails:
    print(f'failures: {len(fails)}')
    sys.exit(1)
print('failures: 0')
