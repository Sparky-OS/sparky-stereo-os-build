#!/usr/bin/python3
"""Test a postinst with real engine records and stub udevadm in a disposable container.

Root is required for the maintainer script and /run/udev fixture; list queries
run as uid 1000. Usage: postinst.py POSTINST LANGDIR OUT
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

script, languages, out = map(Path, sys.argv[1:])
out.mkdir(parents=True, exist_ok=True)
assert os.geteuid() == 0
assert not Path('/run/udev/control').exists(), 'Use a disposable container without udev'
Path('/run/udev').mkdir(exist_ok=True)
failed = 0


def check(condition, description):
    global failed
    print(('PASS ' if condition else 'FAIL ') + description)
    failed += not condition


with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    work.chmod(0o755)
    (work / 'udevadm').write_text('''#!/bin/sh
printf '%s\\n' "$*" >>"$CALLS"
if [ "$FAIL" = yes ]; then echo "udevadm injected failure: $*" >&2; exit 1; fi
echo "udevadm completed: $*"
''')
    (work / 'udevadm').chmod(0o755)
    catalog = work / 'catalog'
    subprocess.run(['sparky-stereo-problems', 'catalog', 'sparky-stereo-kernel-settings', str(languages), str(catalog), '--subject', 'LOCAL1'], check=True)
    env = dict(os.environ, PATH=f'{work}:/usr/bin:/bin', CALLS=str(work / 'calls'),
               HOME='/tmp', XDG_STATE_HOME='/tmp/sparky-stereo-kernel-settings-postinst-test', LC_ALL='C.UTF-8',
               SPARKY_STEREO_PROBLEMS_CATALOG=f'{catalog}:/usr/lib/systemd/catalog')
    subprocess.run(['sparky-stereo-problems', 'clear', '--all', 'sparky-stereo-kernel-settings'], check=True)
    def person():
        os.setgroups([])
        os.setgid(1000)
        os.setuid(1000)
    for case, applies, failure in [('works', True, False), ('fails', True, True),
                                   ('absent', False, True), ('repaired', True, False)]:
        sock = None
        if applies:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            sock.bind('/run/udev/control')
        (work / 'calls').unlink(missing_ok=True)
        result = subprocess.run(['sh', str(script), 'configure', '20261103.1~sparky9~0'], env=dict(env, FAIL='yes' if failure else 'no'), capture_output=True, text=True)
        if sock:
            sock.close()
            Path('/run/udev/control').unlink()
        (out / f'{case}.stdout').write_text(result.stdout)
        (out / f'{case}.stderr').write_text(result.stderr)
        (out / f'{case}.exit').write_text(str(result.returncode)+'\n')
        listed = subprocess.run(['sparky-stereo-problems', 'list', '--json', 'sparky-stereo-kernel-settings'], env=env, preexec_fn=person, capture_output=True, text=True)
        assert listed.returncode == 0, listed.stderr
        (out / f'{case}.json').write_text(listed.stdout)
        records = json.loads(listed.stdout)
        check(result.returncode == 0, f'{case}: maintainer script completes')
        if applies:
            check((work / 'calls').read_text().splitlines() == ['control --reload'], f'{case}: reload runs')
        else:
            check(not (work / 'calls').exists(), 'absent: no command run')
            check('next boot' in result.stderr, 'absent: skip explained')
        if case == 'fails':
            check(result.stderr.count('udevadm injected failure:') >= 1, 'failures: original errors shown')
            check({r.get('key') for r in records} == {'udev-reload'}, 'failures: record kept')
            check(all(r.get('status') == 1 and r.get('repair') == [r.get('command')] for r in records) and len(records)==1, 'failures: status and repair retained')
        elif case == 'absent':
            check(len(records)==1, 'absent: skipping does not claim previous failures repaired')
        else:
            check(records == [], f'{case}: no unresolved problem')
    subprocess.run(['sparky-stereo-problems', 'clear', '--all', 'sparky-stereo-kernel-settings'], check=True)
print(f'{failed} failed checks')
sys.exit(bool(failed))
